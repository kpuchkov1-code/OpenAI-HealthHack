//
//  LiveConsult.swift
//  AmberAI
//
//  "Have Amber sit in on your appointment." You paste the meeting link and put the call
//  on speaker (or it's in person); Amber listens through the mic and transcribes the
//  whole conversation on-device with Apple's Speech framework, then hands the transcript
//  to the same record pipeline everything else uses — clinical facts tagged as a consult,
//  the full transcript kept as a record, a durable brief digested for her working memory.
//
//  Why the mic and not a bot in the meeting: iOS sandboxes an app off other apps' audio,
//  and meeting platforms only admit bots through server-side APIs. A bridge-joining bot
//  would mean streaming the call to a backend — which would break the promise the rest of
//  Records keeps, that nothing leaves the phone to read a record. So Amber joins the only
//  honest way she can on-device: she listens in the room. Nothing is uploaded to
//  transcribe; only the finished text is sent for extraction, exactly like a pasted note.
//
//  The transcriber differs from SpeechRecognizer (the turn-based voice loop): it never
//  stops on a pause. It commits each spoken segment on a silence and immediately opens a
//  fresh recognition request over the same live mic tap, which also sidesteps Speech's
//  per-request duration cap across an appointment that can run many minutes.
//

import SwiftUI
import Speech
import AVFoundation
import Combine

@MainActor
final class ConsultTranscriber: ObservableObject {
    /// Committed spoken segments, oldest first.
    @Published private(set) var segments: [String] = []
    /// The utterance currently being spoken, before it settles into a segment.
    @Published var partial: String = ""
    @Published private(set) var isRunning = false
    @Published var errorText: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceWork: DispatchWorkItem?

    /// The whole transcript so far — committed segments plus the live utterance.
    var transcript: String {
        (segments + [partial])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    /// True once both speech recognition and the microphone are authorised.
    func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechOK else { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        errorText = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // One mic tap for the whole appointment; it feeds whichever request is live.
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()

            isRunning = true
            beginSegment()
        } catch {
            errorText = "Amber couldn't start listening. \(error.localizedDescription)"
            teardownAudio()
            isRunning = false
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        silenceWork?.cancel(); silenceWork = nil
        commitPartial()
        teardownAudio()
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Segments

    /// Opens a fresh recognition request over the already-running mic tap.
    private func beginSegment() {
        guard isRunning else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hasError = error != nil
            Task { @MainActor in
                // Ignore late callbacks from a request we've already rolled past.
                guard let self, self.isRunning, self.request === request else { return }
                if let text, !text.isEmpty {
                    self.partial = text
                    self.resetSilenceTimer()
                }
                if isFinal || hasError { self.rollSegment() }
            }
        }
    }

    /// A held silence ends the current segment. We commit it and immediately open a new
    /// request so the appointment keeps being captured without a gap.
    private func resetSilenceTimer() {
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.rollSegment() }
        }
        silenceWork = work
        // A consult has longer natural pauses than a chat turn, so wait a touch longer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func rollSegment() {
        silenceWork?.cancel(); silenceWork = nil
        commitPartial()
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        if isRunning { beginSegment() }   // the mic tap keeps feeding the new request
    }

    private func commitPartial() {
        let committed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !committed.isEmpty { segments.append(committed) }
        partial = ""
    }

    private func teardownAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }
}

// MARK: - Sheet

/// Records → "Amber joins your appointment". A bot joins the meeting from its link and
/// streams the transcript back (primary); or Amber listens on this device through the mic
/// (fallback). Both paths converge on the same review → save → extract screen.
struct LiveConsultView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var transcriber = ConsultTranscriber()

    enum Phase { case setup, botRunning, listening, review }

    @State private var phase: Phase = .setup
    @State private var meetingLink = ""

    /// The transcript captured by whichever path ran, shown on the review screen.
    @State private var capturedTranscript = ""

    // On-device listen
    @State private var permissionDenied = false

    // Bot
    @State private var botId: String?
    @State private var botStatus = ""
    @State private var botError: String?
    @State private var pollTask: Task<Void, Never>?

    // Recall.ai credentials, entered in-app when not baked into RecallConfig.
    @State private var botConfigured = RecallConfig.isConfigured
    @State private var keyEntryOpen = !RecallConfig.isConfigured
    @State private var recallKey = ""
    @State private var recallRegion = RecallConfig.region

    // Save
    @State private var saving = false
    @State private var savedFactCount: Int?

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .setup: setup
                case .botRunning: botRunning
                case .listening: listening
                case .review: review
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Amber joins the call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button((phase == .botRunning || phase == .listening) ? "Cancel" : "Close") {
                        closeAndCleanUp()
                    }
                    .tint(Theme.amber)
                }
            }
        }
    }

    // MARK: Setup

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Amber joins your appointment", systemImage: "person.2.wave.2")
                        .font(.headline)
                    Text("Paste the meeting link and Amber joins the call as a note-taker — you'll see it in the participants. It transcribes the conversation and pulls the medication, instructions and any red flags straight into your records. You just talk to your doctor.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .cardBackground()

                VStack(alignment: .leading, spacing: 8) {
                    Text("MEETING LINK").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    TextField("https://…  (Zoom, Google Meet, Teams)", text: $meetingLink)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if let url = normalisedLink {
                        Link(destination: url) {
                            Label("Open the meeting yourself", systemImage: "arrow.up.forward.app")
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(Theme.amber)
                    }
                }
                .cardBackground()

                botSettings

                if let botError {
                    Label(botError, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    sendBot()
                } label: {
                    Label("Send Amber into the call", systemImage: "person.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.amber, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .disabled(normalisedLink == nil)
                .opacity(normalisedLink == nil ? 0.5 : 1)

                Label("The call audio passes through Recall.ai's cloud to transcribe — unlike the rest of your records, which stay on your phone. Only send Amber in with everyone's agreement.",
                      systemImage: "cloud")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().padding(.vertical, 2)

                // Fallback: no bot, listen through the mic with the call on speaker.
                VStack(alignment: .leading, spacing: 8) {
                    Text("NO BOT?").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text("You can also put the call on speaker and let Amber listen through this phone's microphone — nothing leaves the device that way.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        beginListening()
                    } label: {
                        Label("Listen on this device instead", systemImage: "waveform.badge.mic")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(Theme.amber)
                    if permissionDenied {
                        Label("Amber needs microphone and speech access. Enable them in Settings.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                .cardBackground()
            }
            .padding()
        }
    }

    @ViewBuilder private var botSettings: some View {
        DisclosureGroup(isExpanded: $keyEntryOpen) {
            VStack(alignment: .leading, spacing: 10) {
                SecureField(botConfigured ? "Key set — paste to replace" : "Recall.ai API key", text: $recallKey)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Text("Region").font(.subheadline)
                    Spacer()
                    Picker("Region", selection: $recallRegion) {
                        ForEach(RecallConfig.regions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.amber)
                }
                Text("The region must match the one your Recall.ai key belongs to.")
                    .font(.caption2).foregroundStyle(.secondary)
                Button {
                    saveRecallConfig()
                } label: {
                    Text("Save key").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.amber, in: Capsule())
                        .foregroundStyle(.white)
                }
                .disabled(recallKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Label("Recall.ai bot settings", systemImage: "key")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if botConfigured {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.steady)
                }
            }
        }
        .tint(Theme.ink)
        .cardBackground()
    }

    // MARK: Bot running

    private var botRunning: some View {
        VStack(spacing: 20) {
            Spacer()
            if botError == nil { PulsingDot().scaleEffect(1.6) }
            Text(botError ?? botStatus)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(botError == nil ? Theme.ink : .red)
                .padding(.horizontal, 32)
            if botError == nil {
                Text("Keep this screen open. When your appointment ends, tap below and Amber will bring the transcript back.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
            if botError == nil {
                Button {
                    endBot()
                } label: {
                    Label("End & bring back the transcript", systemImage: "stop.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.support, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding()
            } else {
                Button {
                    botError = nil
                    phase = .setup
                } label: {
                    Text("Back").font(.headline)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Theme.amber, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding()
            }
        }
    }

    // MARK: Listening (on-device)

    private var listening: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PulsingDot()
                Text("Listening — Amber is transcribing")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding()
            .background(.white)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if transcriber.transcript.isEmpty {
                            Text("Whatever is said out loud will appear here as Amber hears it.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .padding(.top, 24)
                        }
                        ForEach(Array(transcriber.segments.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.subheadline).foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !transcriber.partial.isEmpty {
                            Text(transcriber.partial)
                                .font(.subheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .onChange(of: transcriber.transcript) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            if let err = transcriber.errorText {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Button {
                transcriber.stop()
                capturedTranscript = transcriber.transcript
                phase = .review
            } label: {
                Label("End & save", systemImage: "stop.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.support, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding()
        }
    }

    // MARK: Review & save

    private var review: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let count = savedFactCount {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Saved to your records", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(Theme.steady)
                        Text(count == 0
                             ? "The transcript is kept as a record. Amber found nothing clinical firm enough to pull out — the full text is there for you."
                             : "Amber pulled \(count) \(count == 1 ? "fact" : "facts") into memory — medication, instructions, and any red flags — and kept the full transcript as a record. They're in your report for your doctor too.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .cardBackground()

                    Button { closeAndCleanUp() } label: {
                        Text("Done").font(.headline)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Theme.amber, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHAT AMBER HEARD").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        Text(capturedTranscript.isEmpty ? "Nothing was captured." : capturedTranscript)
                            .font(.system(.footnote, design: .monospaced))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .cardBackground()

                    Button {
                        save()
                    } label: {
                        Group {
                            if saving {
                                HStack(spacing: 8) { ProgressView(); Text("Reading the conversation…") }
                            } else {
                                Label("Save & extract context", systemImage: "sparkles")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Theme.amber, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                    }
                    .disabled(saving || capturedTranscript.isEmpty)
                }
            }
            .padding()
        }
    }

    // MARK: - Actions

    private var normalisedLink: URL? {
        let s = meetingLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let withScheme = s.contains("://") ? s : "https://\(s)"
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url
    }

    // MARK: Bot path

    private func sendBot() {
        botError = nil
        guard let url = normalisedLink else {
            botError = "Paste a valid meeting link first."
            return
        }
        guard RecallConfig.isConfigured else {
            botError = "Add your Recall.ai API key below to send a bot in."
            keyEntryOpen = true
            return
        }
        botId = nil
        botStatus = "Sending Amber into the call…"
        phase = .botRunning
        pollTask = Task { await runBot(meetingURL: url.absoluteString) }
    }

    /// Create the bot, then poll until its transcript is ready (or it fails). No backend,
    /// so we poll rather than take Recall's webhooks.
    private func runBot(meetingURL: String) async {
        do {
            let id = try await Recall.createBot(meetingURL: meetingURL, botName: RecallConfig.botName)
            botId = id
            botStatus = "Amber is joining the call…"

            var donePolls = 0
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 4_000_000_000)
                let snap = try await Recall.fetchBot(id: id)
                botStatus = snap.statusMessage

                if let turl = snap.transcriptURL {
                    botStatus = "Fetching the transcript…"
                    capturedTranscript = try await Recall.downloadTranscript(url: turl)
                    phase = .review
                    return
                }
                if snap.failed {
                    botError = snap.statusMessage
                    return
                }
                if snap.done {
                    // The call is over; the transcript artifact can lag a few seconds.
                    donePolls += 1
                    botStatus = "Processing the transcript…"
                    if donePolls >= 8 {   // ~32s with no transcript — save what we have.
                        capturedTranscript = ""
                        phase = .review
                        return
                    }
                }
            }
        } catch is CancellationError {
            // The user closed the sheet; leaving is handled in closeAndCleanUp.
        } catch {
            botError = (error as? RecallError)?.message ?? error.localizedDescription
        }
    }

    /// End the appointment: ask the bot to leave. The running poll loop then picks up the
    /// transcript once Recall has processed it and moves to the review screen.
    private func endBot() {
        botStatus = "Asking Amber to leave the call…"
        if let id = botId {
            Task { try? await Recall.leaveCall(id: id) }
        }
    }

    private func saveRecallConfig() {
        let k = recallKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        RecallConfig.apiKey = k
        RecallConfig.region = recallRegion
        recallKey = ""
        botConfigured = true
        keyEntryOpen = false
        botError = nil
    }

    // MARK: On-device path

    private func beginListening() {
        permissionDenied = false
        Task {
            guard await transcriber.requestAuthorization() else {
                permissionDenied = true
                return
            }
            phase = .listening
            transcriber.start()
        }
    }

    // MARK: Save & teardown

    private func save() {
        saving = true
        Task {
            let added = await app.addLiveConsult(meetingLink: meetingLink, transcript: capturedTranscript)
            savedFactCount = added.count
            saving = false
        }
    }

    /// Cancel any polling, stop listening, and tell a still-running bot to leave, so we
    /// never leave Amber sitting in an empty meeting after the sheet is gone.
    private func closeAndCleanUp() {
        pollTask?.cancel()
        transcriber.stop()
        if let id = botId {
            Task { try? await Recall.leaveCall(id: id) }
        }
        dismiss()
    }
}

/// A small pulsing red dot for the live-listening state.
private struct PulsingDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(Theme.support)
            .frame(width: 12, height: 12)
            .opacity(on ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
