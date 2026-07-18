//
//  Config.swift
//  AmberAI
//
//  Inference configuration. Runware runs chat + fact extraction + Type-fallback TTS.
//  The real-time voice agent (Talk) runs on OpenAI's Realtime API and carries its own
//  key. Keys default to baked-in values but can be overridden in UserDefaults for the demo.
//

import Foundation

enum RunwareConfig {
    /// Model ids are `creator:family@version`. Verify at https://runware.ai/docs.
    static let textModel = "openai:gpt@5.4-mini"
    /// Vision-capable model for the food-logging estimates (a typed description or a
    /// photo). Kept separate from `textModel` so food uses Claude Sonnet without moving
    /// the chat/extraction pipeline off its own model.
    static let foodModel = "anthropic:claude@sonnet-4.6"
    static let ttsModel = "fishaudio:s2.1@pro"
    /// Optional named voice for the TTS model. Fish Audio has a usable default.
    static let ttsVoice = ""

    private static let keyDefaultsKey = "runware_api_key"
    private static let bakedInKey = "BVCuZNbQX9BDnAoiQDOioFri2XqgZYux"

    static var apiKey: String {
        get {
            let stored = UserDefaults.standard.string(forKey: keyDefaultsKey)
            if let stored, !stored.isEmpty { return stored }
            return bakedInKey
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keyDefaultsKey)
        }
    }

    static var isConfigured: Bool { !apiKey.isEmpty }
}

// MARK: - Recall.ai (meeting bot)

/// Configuration for the meeting-bot path in Records: Amber is sent into a Zoom/Meet/
/// Teams call as a participant, and Recall.ai streams the transcript back. Unlike the
/// on-device listen, the call audio passes through Recall's cloud — so this carries its
/// own key and is only used when the patient explicitly sends the bot in.
///
/// The key and region can be baked in here or entered in-app (stored in UserDefaults),
/// the same override pattern the other providers use. The region MUST match the region
/// your Recall account/key belongs to, or requests will fail.
enum RecallConfig {
    static let regions = ["us-west-2", "us-east-1", "eu-central-1", "ap-northeast-1"]
    /// The name the bot shows in the meeting roster.
    static let botName = "Amber (note-taker)"

    private static let keyDefaultsKey = "recall_api_key"
    private static let regionDefaultsKey = "recall_region"
    /// Paste your Recall.ai key here, or enter it in the Records sheet at runtime.
    private static let bakedInKey = "0c1ecfe0c337e9ff02e15b067c3fb180eaf7abce"
    /// Must match the key's region — this key is an eu-central-1 account.
    private static let defaultRegion = "eu-central-1"

    static var apiKey: String {
        get {
            let stored = UserDefaults.standard.string(forKey: keyDefaultsKey)
            if let stored, !stored.isEmpty { return stored }
            return bakedInKey
        }
        set { UserDefaults.standard.set(newValue, forKey: keyDefaultsKey) }
    }

    static var region: String {
        get {
            let stored = UserDefaults.standard.string(forKey: regionDefaultsKey)
            if let stored, regions.contains(stored) { return stored }
            return defaultRegion
        }
        set { UserDefaults.standard.set(newValue, forKey: regionDefaultsKey) }
    }

    static var apiBase: URL { URL(string: "https://\(region).recall.ai/api/v1")! }
    static var isConfigured: Bool { !apiKey.isEmpty }
}

// MARK: - Oura (wearable)

/// Oura Cloud API v2. Two ways in: a legacy Personal Access Token (Oura deprecated new
/// ones in Dec 2025, but existing tokens still work — the quick path), or an OAuth app's
/// client id/secret for the sign-in flow. Everything is entered in Settings → Advanced and
/// stored in UserDefaults, the same override pattern the inference providers use.
enum OuraConfig {
    static let apiBase = URL(string: "https://api.ouraring.com/v2/usercollection")!

    private static let patKey = "oura_personal_token"
    private static let clientIdKey = "oura_client_id"
    private static let clientSecretKey = "oura_client_secret"
    private static let tokensKey = "oura_oauth_tokens"

    /// Legacy Personal Access Token, if the member has one.
    static var personalToken: String {
        get { UserDefaults.standard.string(forKey: patKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: patKey) }
    }

    static var clientId: String {
        get { UserDefaults.standard.string(forKey: clientIdKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: clientIdKey) }
    }
    static var clientSecret: String {
        get { UserDefaults.standard.string(forKey: clientSecretKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: clientSecretKey) }
    }

    /// OAuth parameters, or nil until a client id/secret is entered.
    static var oauth: OAuthCredentials? {
        guard !clientId.isEmpty, !clientSecret.isEmpty else { return nil }
        return OAuthCredentials(
            clientId: clientId, clientSecret: clientSecret,
            redirectURI: "amberai://oura",
            scope: "personal daily heartrate workout",
            authorizeURL: URL(string: "https://cloud.ouraring.com/oauth/authorize")!,
            tokenURL: URL(string: "https://api.ouraring.com/oauth/token")!,
            callbackScheme: "amberai")
    }

    /// Persisted OAuth tokens (nil when signed out / using a PAT).
    static var tokens: OAuthTokens? {
        get {
            guard let data = UserDefaults.standard.data(forKey: tokensKey) else { return nil }
            return try? JSONDecoder().decode(OAuthTokens.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: tokensKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tokensKey)
            }
        }
    }

    /// True when there's some way to authenticate (a PAT or OAuth credentials).
    static var isConfigured: Bool { !personalToken.isEmpty || oauth != nil }
}

// MARK: - WHOOP (wearable)

/// WHOOP API v2, OAuth 2.0 only. Register a free app at developer.whoop.com to get a
/// client id/secret and register the redirect `amberai://whoop`, then enter the id/secret
/// in Settings → Advanced. WHOOP rotates its refresh token on every use, so the stored
/// tokens are rewritten after each refresh.
enum WhoopConfig {
    static let apiBase = URL(string: "https://api.prod.whoop.com/developer")!

    private static let clientIdKey = "whoop_client_id"
    private static let clientSecretKey = "whoop_client_secret"
    private static let tokensKey = "whoop_oauth_tokens"

    static var clientId: String {
        get { UserDefaults.standard.string(forKey: clientIdKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: clientIdKey) }
    }
    static var clientSecret: String {
        get { UserDefaults.standard.string(forKey: clientSecretKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: clientSecretKey) }
    }

    static var oauth: OAuthCredentials? {
        guard !clientId.isEmpty, !clientSecret.isEmpty else { return nil }
        return OAuthCredentials(
            clientId: clientId, clientSecret: clientSecret,
            redirectURI: "amberai://whoop",
            scope: "read:recovery read:cycles read:sleep read:workout read:profile offline",
            authorizeURL: URL(string: "https://api.prod.whoop.com/oauth/oauth2/auth")!,
            tokenURL: URL(string: "https://api.prod.whoop.com/oauth/oauth2/token")!,
            callbackScheme: "amberai")
    }

    static var tokens: OAuthTokens? {
        get {
            guard let data = UserDefaults.standard.data(forKey: tokensKey) else { return nil }
            return try? JSONDecoder().decode(OAuthTokens.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: tokensKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tokensKey)
            }
        }
    }

    static var isConfigured: Bool { oauth != nil }
}

// MARK: - OpenAI Realtime

/// Configuration for the real-time voice agent (Talk section only). Uses OpenAI's
/// Realtime API over WebSocket: streaming audio in and out, server-side turn detection,
/// and barge-in. This is a different provider from Runware (which still powers the Type
/// fallback and durable-fact extraction), so it carries its own key.
enum OpenAIConfig {
    /// GA realtime model. Swap for a `...-realtime-preview` id if that's what your key has.
    static let realtimeModel = "gpt-realtime"
    /// One of gpt-realtime's voices: marin, cedar, alloy, ash, ballad, coral, echo, sage, shimmer, verse.
    /// Every voice gpt-realtime can speak in — the user picks one in the Talk screen.
    /// marin/cedar are the newest and most natural; the rest are the earlier set.
    static let voices = ["marin", "cedar", "coral", "shimmer", "sage",
                         "alloy", "ash", "ballad", "echo", "verse"]

    private static let voiceDefaultsKey = "openai_voice"
    /// The chosen voice, persisted. Defaults to marin.
    static var voice: String {
        get {
            let stored = UserDefaults.standard.string(forKey: voiceDefaultsKey)
            if let stored, voices.contains(stored) { return stored }
            return "marin"
        }
        set { UserDefaults.standard.set(newValue, forKey: voiceDefaultsKey) }
    }
    /// Transcribes the patient's speech to text, which drives memory + the safety net.
    static let transcriptionModel = "gpt-4o-mini-transcribe"

    private static let keyDefaultsKey = "openai_api_key"
    /// Paste your OpenAI Realtime key (sk-...) here, or set it at runtime via `apiKey`.
    private static let bakedInKey = ""

    static var apiKey: String {
        get {
            let stored = UserDefaults.standard.string(forKey: keyDefaultsKey)
            if let stored, !stored.isEmpty { return stored }
            return bakedInKey
        }
        set { UserDefaults.standard.set(newValue, forKey: keyDefaultsKey) }
    }

    static var isConfigured: Bool { !apiKey.isEmpty }
}
