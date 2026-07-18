//
//  Runware.swift
//  AmberAI
//
//  Minimal, dependency-free Runware client (REST over URLSession). Runware exposes a
//  SINGLE endpoint; every request is an ARRAY of task objects. Ported from lib/runware.ts.
//  Voice is NOT realtime: Runware has no streaming conversation, so the app runs a
//  turn-based loop (speech-to-text -> runwareText -> runwareSpeak -> playback).
//

import Foundation

struct RunwareError: LocalizedError {
    let message: String
    let detail: String?
    var errorDescription: String? { message }
}

struct RunwareMessage: Codable {
    let role: String   // "user" | "assistant"
    let content: String
}

enum Runware {
    private static let endpoint = URL(string: "https://api.runware.ai/v1")!

    private static func post(_ task: [String: Any]) async throws -> [String: Any] {
        let key = RunwareConfig.apiKey
        guard !key.isEmpty else { throw RunwareError(message: "RUNWARE_API_KEY is not set.", detail: nil) }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [task])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw RunwareError(message: "Could not reach Runware.", detail: String(describing: error))
        }

        let bodyText = String(data: data, encoding: .utf8) ?? ""
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RunwareError(message: "Runware \(http.statusCode)", detail: String(bodyText.prefix(400)))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RunwareError(message: "Runware returned a non-JSON body.", detail: String(bodyText.prefix(400)))
        }

        if let errors = json["errors"] as? [[String: Any]], let first = errors.first {
            let msg = (first["message"] as? String) ?? "Runware reported an error."
            throw RunwareError(message: msg, detail: first["parameter"] as? String)
        }

        guard let arr = json["data"] as? [[String: Any]], let item = arr.first else {
            throw RunwareError(message: "Runware returned no data.", detail: String(bodyText.prefix(400)))
        }
        return item
    }

    /// One text-generation turn. System instructions ride `settings.systemPrompt`.
    static func text(system: String, messages: [RunwareMessage], model: String? = nil,
                     temperature: Double = 0.7, maxTokens: Int? = nil) async throws -> String {
        var settings: [String: Any] = ["systemPrompt": system, "temperature": temperature]
        if let maxTokens { settings["maxTokens"] = maxTokens }
        let task: [String: Any] = [
            "taskType": "textInference",
            "taskUUID": UUID().uuidString.lowercased(),
            "model": model ?? RunwareConfig.textModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "settings": settings,
        ]
        let item = try await post(task)
        guard let text = item["text"] as? String else {
            throw RunwareError(message: "Runware returned no text.", detail: nil)
        }
        return text
    }

    /// One vision turn: a text prompt plus a single inline image. Runware's textInference
    /// does NOT take the OpenAI multimodal content array; the image rides a separate
    /// top-level `inputs.images` array (a base64 data URI, hosted URL, or uploaded UUID)
    /// while the message content stays a plain text string. If a model rejects the image
    /// the error surfaces to the caller, which then falls back to a typed description.
    static func visionText(system: String, prompt: String, imageData: Data,
                           model: String? = nil, temperature: Double = 0.2,
                           maxTokens: Int? = 500) async throws -> String {
        let dataURI = "data:image/jpeg;base64," + imageData.base64EncodedString()
        var settings: [String: Any] = ["systemPrompt": system, "temperature": temperature]
        if let maxTokens { settings["maxTokens"] = maxTokens }
        let task: [String: Any] = [
            "taskType": "textInference",
            "taskUUID": UUID().uuidString.lowercased(),
            "model": model ?? RunwareConfig.textModel,
            "messages": [["role": "user", "content": prompt]],
            "inputs": ["images": [dataURI]],
            "settings": settings,
        ]
        let item = try await post(task)
        guard let text = item["text"] as? String else {
            throw RunwareError(message: "Runware returned no text.", detail: nil)
        }
        return text
    }

    /// Text to speech. Returns a hosted audio URL (mp3/wav) to play.
    static func speak(text: String, voice: String? = nil, model: String? = nil) async throws -> URL {
        var speech: [String: Any] = ["text": text]
        let v = voice ?? RunwareConfig.ttsVoice
        if !v.isEmpty { speech["voice"] = v }
        let task: [String: Any] = [
            "taskType": "audioInference",
            "taskUUID": UUID().uuidString.lowercased(),
            "model": model ?? RunwareConfig.ttsModel,
            "speech": speech,
        ]
        let item = try await post(task)
        guard let urlString = item["audioURL"] as? String, let url = URL(string: urlString) else {
            throw RunwareError(message: "Runware returned no audio URL.", detail: nil)
        }
        return url
    }
}

/// Pulls the first JSON object out of a model reply (Runware has no forced-JSON mode).
func parseJsonLoose(_ text: String) -> [String: Any]? {
    var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let g = groups(#"```(?:json)?\s*([\s\S]*?)```"#, candidate, options: [.caseInsensitive]), g.count >= 2 {
        candidate = g[1].trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let data = candidate.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        return obj
    }
    // Fall back to the first balanced { ... } or [ ... ].
    if let start = candidate.firstIndex(where: { $0 == "{" || $0 == "[" }) {
        let endChar: Character = candidate[start] == "{" ? "}" : "]"
        if let end = candidate.lastIndex(of: endChar), end > start {
            let slice = String(candidate[start...end])
            if let data = slice.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
        }
    }
    return nil
}
