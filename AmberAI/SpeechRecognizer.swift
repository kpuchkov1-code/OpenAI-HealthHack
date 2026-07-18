//
//  SpeechRecognizer.swift
//  AmberAI
//
//  The speech-to-text leg of the turn-based voice loop. Apple's on-device Speech
//  framework, en-GB, with a silence detector that finalises an utterance after ~0.9s
//  of quiet — the same pause the web app's server VAD used, chosen because patients
//  pause before they say the thing that matters.
//

import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published private(set) var isListening = false

    /// Called with the final transcript once the speaker pauses.
    var onFinalUtterance: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceWork: DispatchWorkItem?

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

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    func startListening() throws {
        guard !isListening else { return }
        task?.cancel()
        task = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        transcript = ""
        isListening = true

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hasError = error != nil
            Task { @MainActor in
                guard let self else { return }
                if let text, !text.isEmpty {
                    self.transcript = text
                    self.resetSilenceTimer()
                }
                if hasError || isFinal { self.finishUtterance() }
            }
        }
    }

    func stopListening() {
        silenceWork?.cancel()
        silenceWork = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
    }

    // MARK: - Silence detection

    private func resetSilenceTimer() {
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.finishUtterance() }
        }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func finishUtterance() {
        silenceWork?.cancel()
        silenceWork = nil
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopListening()
        if !text.isEmpty { onFinalUtterance?(text) }
    }
}
