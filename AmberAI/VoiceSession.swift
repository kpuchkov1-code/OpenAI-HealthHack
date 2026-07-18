//
//  VoiceSession.swift
//  AmberAI
//
//  The real-time voice loop. Amber now streams both ways over OpenAI's Realtime API:
//  your speech goes up as audio, her reply comes back as audio, and the server decides
//  when a turn ends. You can talk over her (barge-in) and she stops.
//
//  This class keeps the app's thesis intact around that stream:
//    - Instructions are built from buildInstructions(state, week), so memory is still a
//      function of time — scrub the week back and Amber genuinely knows less.
//    - Every completed exchange runs through commitExchange, so stated facts still land
//      in Memory live (the proof beat), and durable-fact extraction is unchanged.
//    - checkSafety still gates each utterance: a flagged line is never answered by the
//      model; Amber says the safe line instead.
//
//  The Type box remains a full fallback: typed while live it joins the voice
//  conversation; typed cold it answers via the Runware brain, text only.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class VoiceSession: ObservableObject {
    enum Status { case idle, connecting, live, error }

    @Published var status: Status = .idle
    @Published var speaking = false
    @Published var thinking = false
    @Published var errorMessage: String?
    @Published var safety: SafetyHit?
    /// The resource Amber has offered this turn, surfaced as a tappable card. Nil until she
    /// calls the suggest_resource tool, cleared when the person taps or dismisses it.
    @Published var signpost: Signpost?
    /// The visible conversation for this session (separate from persisted memory).
    @Published var conversation: [Turn] = []
    /// Live partial transcript of what you're saying, while you speak.
    @Published var partialTranscript = ""
    /// True while the mic is open and streaming to the model.
    @Published private(set) var isListening = false

    private let audio = RealtimeAudioEngine()
    private var client: OpenAIRealtimeClient?
    private weak var app: AppState?

    /// Turn assembly: we stitch streamed transcript deltas into whole lines, then pair
    /// the user's line with Amber's to feed the memory writer.
    private var assistantText = ""
    private var pendingUserText: String?
    /// Set when Amber saves a fact herself via the `remember` tool during a turn, so the
    /// passive extractor is skipped for that turn and the fact isn't written twice.
    private var toolWroteThisTurn = false

    func attach(_ app: AppState) { self.app = app }

    // MARK: - Session control

    func connect() async {
        guard let app else { return }
        guard OpenAIConfig.isConfigured else {
            status = .error
            errorMessage = "Add your OpenAI key in Config.swift to talk to Amber."
            return
        }
        status = .connecting

        let granted = await requestMicrophone()
        guard granted else {
            status = .error
            errorMessage = "The microphone was refused. Enable it in Settings, or use Type instead."
            return
        }

        // Fold older facts into their summaries and brief her whole records before the
        // session's instructions are built in handleOpen, so the realtime model reads the
        // compact memory and the record digests too.
        await app.consolidateMemoryIfNeeded()
        await app.digestRecordsIfNeeded()

        let client = OpenAIRealtimeClient(key: OpenAIConfig.apiKey, model: OpenAIConfig.realtimeModel)
        self.client = client
        client.onOpen = { [weak self] in Task { @MainActor in self?.handleOpen() } }
        client.onEvent = { [weak self] event in Task { @MainActor in self?.handle(event) } }
        client.onError = { [weak self] message in Task { @MainActor in self?.fail(message) } }
        _ = app  // keep the reference alive; used from handleOpen onward
        client.connect()
    }

    func disconnect() {
        audio.onMicChunk = nil
        audio.stop()
        client?.close()
        client = nil
        isListening = false
        speaking = false
        thinking = false
        partialTranscript = ""
        assistantText = ""
        pendingUserText = nil
        toolWroteThisTurn = false
        signpost = nil
        if status != .error { status = .idle }
    }

    // MARK: - Realtime wiring

    private func handleOpen() {
        guard let app, let client else { return }

        // Configure the session: Amber's memory-scoped instructions, her voice, PCM16
        // both ways, server VAD with barge-in, and transcription of your speech.
        client.send(sessionUpdate(instructions: buildInstructions(app.state, app.week, wearables: wearablesPromptBlock(app.wearableSummaries))))

        // Open the mic and stream it up. Capture the client directly so the audio-thread
        // closure never touches main-actor state.
        let transport = client
        audio.onMicChunk = { data in
            transport.send(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()])
        }
        do {
            try audio.start()
            isListening = true
            status = .live
        } catch {
            fail("Could not start audio: \(error.localizedDescription)")
            return
        }

        // If she's been left quiet, Amber opens the conversation herself.
        if let cue = openerCue(app.week, proactive: app.state.consent.proactiveOutreach) {
            client.send(["type": "response.create", "response": ["instructions": cue]])
        }
    }

    private func handle(_ event: [String: Any]) {
        guard let type = event["type"] as? String else { return }
        switch type {
        case "session.created", "session.updated", "response.created":
            if type == "response.created" { thinking = true }

        // You started talking over Amber: cut her audio immediately (server also cancels).
        case "input_audio_buffer.speech_started":
            audio.interruptPlayback()
            speaking = false

        // Amber's voice, streamed. Play as it arrives. (Handle GA + preview event names.)
        case "response.output_audio.delta", "response.audio.delta":
            if let b64 = event["delta"] as? String, let data = Data(base64Encoded: b64) {
                thinking = false
                speaking = true
                audio.enqueue(pcm16: data)
            }

        // Amber's words, streamed — assembled for the on-screen bubble + memory.
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            if let delta = event["delta"] as? String { assistantText += delta }

        // Your words, streamed then finalised.
        case "conversation.item.input_audio_transcription.delta":
            if let delta = event["delta"] as? String { partialTranscript += delta }
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = event["transcript"] as? String { userFinished(transcript) }

        // Amber decided to save a memory herself. Land it and hand the result back so she
        // can carry on speaking. Arrives before response.done for this turn.
        case "response.function_call_arguments.done":
            handleToolCall(event)

        case "response.done":
            assistantFinished()

        case "error":
            let message = (event["error"] as? [String: Any])?["message"] as? String
            fail(message ?? "The voice connection reported an error.")

        default:
            break
        }
    }

    // MARK: - Turn completion

    private func userFinished(_ text: String) {
        partialTranscript = ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let app, let client else { return }

        conversation.append(Turn(role: .user, text: trimmed, week: app.week, at: Date().timeIntervalSince1970))

        // Safety net: a flagged utterance is never answered by the model. Cancel whatever
        // the server VAD started and have Amber say the safe line in her own voice.
        if let hit = checkSafety(trimmed) {
            safety = hit
            signpost = nil   // crisis takes the screen; never signpost a service over it
            audio.interruptPlayback()
            client.send(["type": "response.cancel"])
            client.send(["type": "response.create",
                         "response": ["instructions": "Say exactly this, warmly, and nothing else: \(safetyReply(hit))"]])
            pendingUserText = nil
            return
        }
        pendingUserText = trimmed
    }

    private func assistantFinished() {
        thinking = false
        speaking = false
        let reply = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        assistantText = ""
        guard !reply.isEmpty, let app else { return }

        conversation.append(Turn(role: .ember, text: reply, week: app.week, at: Date().timeIntervalSince1970))

        // Write the exchange to memory. If Amber already saved a fact herself this turn via
        // the remember tool, skip the passive extractor so the same fact isn't written twice.
        if let user = pendingUserText {
            pendingUserText = nil
            let extract = !toolWroteThisTurn
            toolWroteThisTurn = false
            Task { await app.commitExchange(user: user, amber: reply, at: Date().timeIntervalSince1970, extract: extract) }
        }
    }

    /// Amber called the `remember` tool. Land the fact through AppState (which dedupes and
    /// honours the personal-memory consent gate), then return the outcome to the model and
    /// ask it to continue so she speaks her follow-up in the same breath.
    private func handleToolCall(_ event: [String: Any]) {
        guard let app, let client else { return }
        let callId = event["call_id"] as? String ?? ""
        let name = event["name"] as? String

        let args = (event["arguments"] as? String)
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }

        var output = "ok"
        if name == "remember", let obj = args {
            let content = (obj["content"] as? String) ?? ""
            let typeRaw = (obj["type"] as? String) ?? "personal"
            let sal = (obj["salience"] as? Double) ?? (obj["salience"] as? NSNumber)?.doubleValue ?? 0.6
            if app.rememberFact(content: content, typeRaw: typeRaw, salience: sal) != nil {
                toolWroteThisTurn = true
                output = "saved"
            } else {
                output = "not saved"
            }
        } else if name == "suggest_resource", let obj = args {
            // Only surface a door when it's real and she isn't already in a safety moment;
            // crisis always wins the screen.
            if let hit = resolveSignpost((obj["resource"] as? String) ?? ""), safety == nil {
                signpost = hit
                output = "shown"
            } else {
                output = "not shown"
            }
        }

        client.send(["type": "conversation.item.create",
                     "item": ["type": "function_call_output", "call_id": callId, "output": output]])
        client.send(["type": "response.create"])
    }

    // MARK: - Type fallback

    /// Works whether or not the voice session is live. Live: the typed line joins the
    /// voice conversation and Amber answers aloud. Cold: the Runware brain answers in text.
    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let app else { return }

        conversation.append(Turn(role: .user, text: trimmed, week: app.week, at: Date().timeIntervalSince1970))

        if let hit = checkSafety(trimmed) {
            safety = hit
            let line = safetyReply(hit)
            if status == .live, let client {
                audio.interruptPlayback()
                client.send(["type": "response.cancel"])
                client.send(["type": "response.create",
                             "response": ["instructions": "Say exactly this, warmly, and nothing else: \(line)"]])
            } else {
                conversation.append(Turn(role: .ember, text: line, week: app.week, at: Date().timeIntervalSince1970))
            }
            return
        }

        if status == .live, let client {
            pendingUserText = trimmed
            client.send(["type": "conversation.item.create",
                         "item": ["type": "message", "role": "user",
                                  "content": [["type": "input_text", "text": trimmed]]]])
            client.send(["type": "response.create"])
        } else {
            thinking = true
            Task {
                let outcome = await app.reply(to: trimmed)
                thinking = false
                if let hit = outcome.safety { safety = hit }
                if !outcome.reply.isEmpty {
                    conversation.append(Turn(role: .ember, text: outcome.reply, week: app.week, at: Date().timeIntervalSince1970))
                    await app.commitExchange(user: trimmed, amber: outcome.reply, at: Date().timeIntervalSince1970)
                } else if let err = app.lastError {
                    errorMessage = err
                }
            }
        }
    }

    // MARK: - Helpers

    private func fail(_ message: String) {
        errorMessage = message
        status = .error
        disconnect()
        status = .error
    }

    private func requestMicrophone() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
        }
    }

    /// The GA Realtime `session.update` payload: instructions, voice, PCM16 both ways,
    /// server VAD (with barge-in), and speech transcription.
    private func sessionUpdate(instructions: String) -> [String: Any] {
        [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "instructions": instructions,
                "output_modalities": ["audio"],
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "turn_detection": [
                            "type": "server_vad",
                            "threshold": 0.5,
                            "prefix_padding_ms": 300,
                            "silence_duration_ms": 600,
                            "create_response": true,
                            "interrupt_response": true,
                        ],
                        "transcription": ["model": OpenAIConfig.transcriptionModel],
                    ],
                    "output": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "voice": OpenAIConfig.voice,
                    ],
                ],
                "tools": [rememberTool, suggestResourceTool],
                "tool_choice": "auto",
            ],
        ]
    }

    /// The one tool Amber has: she may write to her own memory the moment something is
    /// worth keeping, rather than waiting for the passive post-turn extractor. She is told
    /// not to announce it — saving should be invisible, like a person who simply remembers.
    private var rememberTool: [String: Any] {
        [
            "type": "function",
            "name": "remember",
            "description": """
            Save one durable fact about the patient to long-term memory the moment she \
            tells you something worth remembering in three weeks: a symptom or its pattern, \
            a medication detail, something her prescriber told her, something that matters \
            in her life, or something she finds hard. Do not say that you are saving it. \
            Do not use this for passing small talk or anything only true today.
            """,
            "parameters": [
                "type": "object",
                "properties": [
                    "content": [
                        "type": "string",
                        "description": "The fact in the third person about him, one short clause, present tense where possible. E.g. \"Nausea peaks on day 3 after his dose\".",
                    ],
                    "type": [
                        "type": "string",
                        "enum": ["symptom", "medication", "clinical_instruction", "personal", "struggle"],
                        "description": "Use personal for anything about his life that is not about the drug.",
                    ],
                    "salience": [
                        "type": "number",
                        "description": "0 to 1: how much this should shape future conversations.",
                    ],
                ],
                "required": ["content", "type"],
            ],
        ]
    }

    /// Amber's other tool: offer the person a real door when she has said she's looking for
    /// one. Calling it puts a tappable card on screen while Amber names it aloud. The
    /// restraint (only when she raised the need, one gentle offer) lives in the prompt.
    private var suggestResourceTool: [String: Any] {
        [
            "type": "function",
            "name": "suggest_resource",
            "description": """
            Offer the person a partner service by putting a tappable card on her screen, \
            ONLY when she has herself named a need you cannot meet: wanting a doctor or \
            prescriber, low mood or wanting to talk to a therapist (not a crisis), real \
            help with eating or nutrition, or help getting active. Do not use this to \
            upsell, do not fish for openings, and do not offer the same resource twice. \
            You still say it aloud in your own words; this only surfaces the card.
            """,
            "parameters": [
                "type": "object",
                "properties": [
                    "resource": [
                        "type": "string",
                        "enum": SignpostCategory.allCases.map { $0.rawValue },
                        "description": "Which door to open: find_doctor, therapy, nutrition, or movement.",
                    ],
                ],
                "required": ["resource"],
            ],
        ]
    }
}
