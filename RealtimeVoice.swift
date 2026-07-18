//
//  RealtimeVoice.swift
//  AmberAI
//
//  The transport for the real-time voice agent: a WebSocket to OpenAI's Realtime API
//  and a full-duplex audio engine. Deliberately dumb — it moves bytes and events, it
//  holds no product logic. VoiceSession orchestrates it and owns the memory pipeline.
//
//  Audio is 24 kHz mono PCM16 in both directions, the Realtime API's native format.
//  The mic stays open during playback (for barge-in), so we run the audio session in
//  .voiceChat mode to get hardware echo cancellation and stop Amber hearing herself.
//

import Foundation
import AVFoundation

// MARK: - Audio engine (capture + playback)

/// Captures the microphone as 24 kHz mono PCM16 and plays back streamed PCM16 audio.
/// Not main-actor bound: `onMicChunk` fires on the audio render thread.
final class RealtimeAudioEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 24_000

    /// What we send to OpenAI: interleaved 24 kHz mono signed-16.
    private let wireFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                           sampleRate: 24_000, channels: 1, interleaved: true)!
    /// What the player node runs: 24 kHz mono float (the engine converts to hardware rate).
    private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!

    private var converter: AVAudioConverter?

    /// Count of playback chunks queued-but-not-finished. Guarded because it's touched
    /// from the audio render thread (mic tap) and the main actor (enqueue/interrupt).
    private let pendingLock = NSLock()
    private var pendingPlaybackChunks = 0

    /// Called with one chunk of base64-ready PCM16 mic audio, on the audio thread.
    var onMicChunk: ((Data) -> Void)?

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: wireFormat)
        input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            self?.forwardMic(buffer)
        }

        engine.prepare()
        try engine.start()
        player.play()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        if engine.isRunning { engine.stop() }
        converter = nil
        setPending(0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Barge-in: drop everything queued and still playing so Amber goes quiet at once.
    func interruptPlayback() {
        player.stop()
        setPending(0)
        if engine.isRunning { player.play() }
    }

    /// Queue a chunk of Amber's speech (24 kHz mono PCM16) for playback.
    func enqueue(pcm16 data: Data) {
        let frames = data.count / MemoryLayout<Int16>.size
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat,
                                            frameCapacity: AVAudioFrameCount(frames)) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        let out = buffer.floatChannelData![0]
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<frames { out[i] = Float(samples[i]) / 32_768.0 }
        }
        adjustPending(+1)
        player.scheduleBuffer(buffer) { [weak self] in self?.adjustPending(-1) }
        if engine.isRunning, !player.isPlaying { player.play() }
    }

    // MARK: Echo control

    private func adjustPending(_ delta: Int) {
        pendingLock.lock()
        pendingPlaybackChunks = max(0, pendingPlaybackChunks + delta)
        pendingLock.unlock()
    }

    private func setPending(_ value: Int) {
        pendingLock.lock()
        pendingPlaybackChunks = value
        pendingLock.unlock()
    }

    /// Half-duplex guard: while Amber's audio is actually playing out of the *built-in
    /// speaker*, don't stream the mic — otherwise she hears herself over the air and
    /// answers her own voice. With headphones or the earpiece there's no acoustic loop,
    /// so we stay full-duplex and keep barge-in.
    private func suppressMicForEcho() -> Bool {
        pendingLock.lock()
        let playing = pendingPlaybackChunks > 0
        pendingLock.unlock()
        guard playing else { return false }
        return AVAudioSession.sharedInstance().currentRoute.outputs
            .contains { $0.portType == .builtInSpeaker }
    }

    private func forwardMic(_ buffer: AVAudioPCMBuffer) {
        if suppressMicForEcho() { return }
        guard let converter else { return }
        let ratio = sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let out = AVAudioPCMBuffer(pcmFormat: wireFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let channel = out.int16ChannelData else { return }
        let data = Data(bytes: channel[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size)
        onMicChunk?(data)
    }
}

// MARK: - WebSocket client

/// A thin OpenAI Realtime WebSocket client. Sends JSON events, decodes JSON events,
/// and reports open/error. All callbacks may arrive off the main thread.
final class OpenAIRealtimeClient: NSObject, URLSessionWebSocketDelegate {
    var onOpen: (() -> Void)?
    var onEvent: (([String: Any]) -> Void)?
    var onError: ((String) -> Void)?

    private let key: String
    private let model: String
    private var task: URLSessionWebSocketTask?
    private var closed = false

    init(key: String, model: String) {
        self.key = key
        self.model = model
    }

    func connect() {
        var comps = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        comps.queryItems = [URLQueryItem(name: "model", value: model)]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        // Preview models still expect the beta header; the GA model ignores it.
        if model.contains("preview") {
            req.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        }
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: req)
        self.task = task
        task.resume()
        receive()
    }

    func send(_ event: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let string = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(string)) { [weak self] error in
            if let error, self?.closed == false { self?.onError?(error.localizedDescription) }
        }
    }

    func close() {
        closed = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self, !self.closed else { return }
            switch result {
            case .failure(let error):
                self.onError?(error.localizedDescription)
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.onEvent?(obj)
                    }
                case .data(let data):
                    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.onEvent?(obj)
                    }
                @unknown default:
                    break
                }
                self.receive()
            }
        }
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        onOpen?()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if !closed {
            let text = reason.flatMap { String(data: $0, encoding: .utf8) }
            onError?(text?.isEmpty == false ? text! : "The voice connection closed.")
        }
    }
}
