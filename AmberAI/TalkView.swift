//
//  TalkView.swift
//  AmberAI
//
//  The companion. A calm, centred home: one orb, tap to talk. The moment a session
//  starts, the app rises into a full-screen call with Amber — streaming voice, live
//  captions, barge-in. Type is always there as a quiet fallback. Same memory pipeline
//  underneath: what you say still lands in Memory.
//

import SwiftUI

struct TalkView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var session = VoiceSession()
    @State private var inCall = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                RadialGradient(colors: [Theme.amberSoft.opacity(0.35), .clear],
                               center: .center, startRadius: 8, endRadius: 460)
                    .ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()

                    VStack(spacing: 8) {
                        Text("Amber")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        Text("The companion that remembers.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: startCall) {
                        AmberOrb(status: .idle, speaking: false, listening: false, size: 168)
                    }
                    .buttonStyle(OrbPressStyle())

                    Text(session.status == .error ? (session.errorMessage ?? "Something went wrong")
                                                   : "Tap to talk")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(session.status == .error ? Theme.support : .secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()

                    Button {
                        startCall()
                    } label: {
                        Label("Type instead", systemImage: "keyboard")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink.opacity(0.7))
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .background(.white, in: Capsule())
                            .overlay(Capsule().stroke(Theme.amberSoft.opacity(0.6)))
                    }
                    .padding(.bottom, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { VoicePickerMenu(session: session) }
            }
        }
        .onAppear { session.attach(app) }
        .fullScreenCover(isPresented: $inCall) {
            TalkCallView(session: session) {
                session.disconnect()
                inCall = false
            }
            .environmentObject(app)
        }
        .onChange(of: session.status) { _, status in
            // A failed connection drops us back to the calm home with the reason shown.
            if status == .error { inCall = false }
        }
    }

    private func startCall() {
        inCall = true
        if session.status != .live {
            Task { await session.connect() }
        }
    }
}

// MARK: - Full-screen call

/// The immersive conversation. Big orb, live captions, controls. Presented while a
/// session is connecting or live; dismissed when it ends.
private struct TalkCallView: View {
    @ObservedObject var session: VoiceSession
    @EnvironmentObject var app: AppState
    var onEnd: () -> Void

    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [Theme.amberSoft.opacity(0.55), .clear],
                           center: .init(x: 0.5, y: 0.34), startRadius: 10, endRadius: 520)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                orbSection
                    .padding(.top, 6)

                if let hit = session.safety {
                    SafetyCardView(hit: hit) { session.safety = nil }
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if let signpost = session.signpost {
                    SignpostCardView(signpost: signpost) { session.signpost = nil }
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                transcript
                    .padding(.top, 8)

                if !app.lastAddedFactIds.isEmpty {
                    rememberedChip
                        .padding(.bottom, 6)
                        .transition(.opacity)
                }

                composer
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)

                endButton
                    .padding(.top, 10)
                    .padding(.bottom, 18)
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                onEnd()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink.opacity(0.6))
                    .frame(width: 38, height: 38)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(Theme.amberSoft.opacity(0.5)))
            }
            Spacer()
            VoicePickerMenu(session: session)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.white, in: Capsule())
                .overlay(Capsule().stroke(Theme.amberSoft.opacity(0.5)))
        }
    }

    // MARK: Orb + status

    private var orbSection: some View {
        VStack(spacing: 14) {
            AmberOrb(status: session.status,
                     speaking: session.speaking,
                     listening: session.isListening && !session.speaking,
                     size: 176)
                .padding(.top, 12)

            Text("Amber")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)

            Text(statusLine)
                .font(.callout.weight(.medium))
                .foregroundStyle(session.status == .error ? Theme.support : .secondary)
                .animation(.easeInOut, value: statusLine)
        }
    }

    private var statusLine: String {
        switch session.status {
        case .idle: return "Ready"
        case .connecting: return "Connecting…"
        case .live:
            if session.speaking { return "Amber is speaking" }
            if session.thinking { return "Thinking…" }
            return "Listening"
        case .error: return session.errorMessage ?? "Something went wrong"
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(session.conversation) { turn in
                        bubble(turn).id(turn.id)
                    }
                    if session.isListening, !session.partialTranscript.isEmpty {
                        bubble(Turn(role: .user, text: session.partialTranscript,
                                    week: app.week, at: 0))
                            .opacity(0.5)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: session.conversation.count) { _, _ in
                if let last = session.conversation.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func bubble(_ turn: Turn) -> some View {
        HStack {
            if turn.role == .ember {
                Text(turn.text)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.amberSoft.opacity(0.5)))
                Spacer(minLength: 44)
            } else {
                Spacer(minLength: 44)
                Text(turn.text)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.amber, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var rememberedChip: some View {
        Label("Amber remembered something new", systemImage: "sparkles")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.amber)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.amberSoft.opacity(0.28), in: Capsule())
    }

    // MARK: Composer + end

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Type a message…", text: $draft, axis: .vertical)
                .focused($typing)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(.white, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.amberSoft.opacity(0.55)))
                .onSubmit(sendDraft)

            Button(action: sendDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.5) : Theme.amber)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || session.thinking)
        }
    }

    private var endButton: some View {
        Button(action: onEnd) {
            HStack(spacing: 8) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                Text("End")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28).padding(.vertical, 14)
            .background(Theme.support, in: Capsule())
            .shadow(color: Theme.support.opacity(0.3), radius: 10, y: 4)
        }
    }

    private func sendDraft() {
        let text = draft
        draft = ""
        typing = false
        session.send(text)
    }
}

// MARK: - The orb

/// Amber's presence. A warm gradient sphere that breathes, brightens when she speaks,
/// and swaps its glyph with the session state.
struct AmberOrb: View {
    var status: VoiceSession.Status
    var speaking: Bool
    var listening: Bool
    var size: CGFloat = 168

    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.amber.opacity(0.16))
                .frame(width: size * 1.55, height: size * 1.55)
                .scaleEffect(speaking ? 1.18 : (listening ? 1.08 : 1.0))
                .blur(radius: 16)
                .animation(.easeInOut(duration: 0.45), value: speaking)
                .animation(.easeInOut(duration: 0.45), value: listening)

            Circle()
                .fill(RadialGradient(colors: [Theme.amberSoft, Theme.amber],
                                     center: .init(x: 0.4, y: 0.34),
                                     startRadius: 2, endRadius: size * 0.66))
                .frame(width: size, height: size)
                .scaleEffect(breathe ? 1.035 : 0.98)
                .shadow(color: Theme.amber.opacity(0.45), radius: speaking ? 30 : 16, y: 8)

            Image(systemName: icon)
                .font(.system(size: size * 0.26, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private var icon: String {
        switch status {
        case .idle: return "mic.fill"
        case .connecting: return "ellipsis"
        case .live: return speaking ? "waveform" : "mic.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

/// A soft press-scale for the home orb.
private struct OrbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Voice picker

/// The end-user's voice choice, across every voice gpt-realtime can speak in. Persisted;
/// if she's mid-call, the session re-establishes so the new voice is heard at once.
struct VoicePickerMenu: View {
    @ObservedObject var session: VoiceSession
    @State private var voice = OpenAIConfig.voice

    var body: some View {
        Menu {
            Picker("Amber's voice", selection: $voice) {
                ForEach(OpenAIConfig.voices, id: \.self) { name in
                    Text(name.capitalized).tag(name)
                }
            }
        } label: {
            Label(voice.capitalized, systemImage: "waveform.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink.opacity(0.75))
        }
        .onChange(of: voice) { _, new in
            OpenAIConfig.voice = new
            if session.status == .live || session.status == .connecting {
                session.disconnect()
                Task { await session.connect() }
            }
        }
    }
}
