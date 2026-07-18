//
//  Recall.swift
//  AmberAI
//
//  Minimal, dependency-free Recall.ai client (REST over URLSession). Recall.ai sends a
//  bot into a Zoom / Google Meet / Microsoft Teams call as a visible participant and
//  streams the transcript back, so Amber can "join" an appointment without the patient
//  having to put the call on speaker.
//
//  This app has no backend to receive Recall's webhooks, so we use the polling model:
//  create a bot with the `recallai_streaming` transcript provider (which also persists
//  the transcript on the recording after the call), then poll GET /bot/{id} until the
//  transcript's presigned download URL appears, and fetch it. The flattened text is
//  handed to the same `addLiveConsult` pipeline the on-device listen uses.
//
//  The call audio passes through Recall's cloud — the one place in Records where a record
//  is not read purely on-device — which is why it is gated behind an explicit "send the
//  bot in" action and its own key.
//

import Foundation

struct RecallError: LocalizedError {
    let message: String
    let detail: String?
    var errorDescription: String? { message }
}

/// A snapshot of a bot's state, distilled from GET /bot/{id} into just what the UI needs.
struct RecallBotSnapshot {
    /// The raw latest status code, e.g. "in_call_recording", "done", "fatal".
    let statusCode: String
    /// A patient-facing line describing where the bot is.
    let statusMessage: String
    /// Present once the meeting's transcript has been processed and is ready to download.
    let transcriptURL: URL?
    /// The bot has finished the call and post-processing.
    let done: Bool
    /// The bot hit a terminal error (could not join, was removed, etc.).
    let failed: Bool
}

enum Recall {

    // MARK: - Requests

    /// Send a bot into a meeting. Returns the bot id used for polling and leaving.
    static func createBot(meetingURL: String, botName: String) async throws -> String {
        let body: [String: Any] = [
            "meeting_url": meetingURL,
            "bot_name": botName,
            "recording_config": [
                "transcript": ["provider": ["recallai_streaming": [:]]],
            ],
        ]
        let json = try await post("/bot", body: body)
        guard let id = json["id"] as? String else {
            throw RecallError(message: "Recall didn't return a bot id.", detail: nil)
        }
        return id
    }

    /// Poll a bot's current state.
    static func fetchBot(id: String) async throws -> RecallBotSnapshot {
        let json = try await get("/bot/\(id)")

        // Latest status: the newer API exposes an ordered `status_changes` array; fall
        // back to a top-level `status.code` for older shapes.
        var code = "unknown"
        if let changes = json["status_changes"] as? [[String: Any]],
           let last = changes.last, let c = last["code"] as? String {
            code = c
        } else if let status = json["status"] as? [String: Any], let c = status["code"] as? String {
            code = c
        } else if let c = json["status"] as? String {
            code = c
        }

        let transcriptURL = transcriptDownloadURL(from: json)
        let failed = ["fatal", "error", "call_not_started", "recording_permission_denied"].contains(code)
        let done = code == "done" || code == "analysis_done"

        return RecallBotSnapshot(
            statusCode: code,
            statusMessage: friendlyStatus(code),
            transcriptURL: transcriptURL,
            done: done,
            failed: failed)
    }

    /// Ask the bot to leave the call. Polling afterwards will pick up the transcript.
    static func leaveCall(id: String) async throws {
        _ = try await post("/bot/\(id)/leave_call", body: [:])
    }

    /// Download and flatten the meeting transcript into speaker-labelled lines.
    static func downloadTranscript(url: URL) async throws -> String {
        // The download URL is presigned; it carries its own auth, so no header is sent.
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RecallError(message: "Couldn't download the transcript (\(http.statusCode)).", detail: nil)
        }
        return flatten(data)
    }

    // MARK: - Transcript shaping

    /// recordings[0].media_shortcuts.transcript.data.download_url, guarded at every hop.
    private static func transcriptDownloadURL(from json: [String: Any]) -> URL? {
        guard let recordings = json["recordings"] as? [[String: Any]],
              let recording = recordings.first,
              let shortcuts = recording["media_shortcuts"] as? [String: Any],
              let transcript = shortcuts["transcript"] as? [String: Any],
              let dataObj = transcript["data"] as? [String: Any],
              let urlString = dataObj["download_url"] as? String,
              let url = URL(string: urlString) else { return nil }
        return url
    }

    /// The transcript JSON is an array of segments, each a speaker and their words. Both
    /// the newer (`participant.name`) and older (`speaker`) shapes are handled, and the
    /// words are joined back into a line so the fact extractor reads a real conversation.
    private static func flatten(_ data: Data) -> String {
        let root = try? JSONSerialization.jsonObject(with: data)
        let segments: [[String: Any]]
        if let arr = root as? [[String: Any]] {
            segments = arr
        } else if let obj = root as? [String: Any], let arr = obj["transcript"] as? [[String: Any]] {
            segments = arr
        } else {
            return ""
        }

        var lines: [String] = []
        for seg in segments {
            let speaker: String
            if let p = seg["participant"] as? [String: Any], let n = p["name"] as? String, !n.isEmpty {
                speaker = n
            } else if let s = seg["speaker"] as? String, !s.isEmpty {
                speaker = s
            } else {
                speaker = "Speaker"
            }
            let words = (seg["words"] as? [[String: Any]]) ?? []
            let text = words.compactMap { $0["text"] as? String }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { lines.append("\(speaker): \(text)") }
        }
        return lines.joined(separator: "\n")
    }

    private static func friendlyStatus(_ code: String) -> String {
        switch code {
        case "ready": return "Amber is getting ready…"
        case "joining_call": return "Amber is joining the call…"
        case "in_waiting_room": return "Amber is in the waiting room — let it in from the call."
        case "in_call_not_recording": return "Amber has joined; waiting to start recording…"
        case "in_call_recording", "recording_permission_allowed": return "Amber is in the call, transcribing live."
        case "call_ended": return "The call ended — Amber is writing up the transcript…"
        case "done", "analysis_done": return "Transcript ready."
        case "recording_permission_denied": return "Recording permission was denied in the meeting."
        case "fatal", "error": return "Amber couldn't join that meeting."
        default: return "Working…"
        }
    }

    // MARK: - HTTP

    private static func get(_ path: String) async throws -> [String: Any] {
        try await send(path, method: "GET", body: nil)
    }

    private static func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        try await send(path, method: "POST", body: body)
    }

    private static func send(_ path: String, method: String, body: [String: Any]?) async throws -> [String: Any] {
        let key = RecallConfig.apiKey
        guard !key.isEmpty else { throw RecallError(message: "No Recall.ai API key set.", detail: nil) }

        let url = RecallConfig.apiBase.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw RecallError(message: "Could not reach Recall.ai.", detail: String(describing: error))
        }

        let bodyText = String(data: data, encoding: .utf8) ?? ""
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let hint = http.statusCode == 401
                ? "Recall rejected the key — check the key and that its region matches."
                : "Recall.ai \(http.statusCode)"
            throw RecallError(message: hint, detail: String(bodyText.prefix(400)))
        }

        // A 200 with an empty body (e.g. leave_call) is fine; hand back an empty object.
        if data.isEmpty { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RecallError(message: "Recall.ai returned an unexpected body.", detail: String(bodyText.prefix(400)))
        }
        return json
    }
}
