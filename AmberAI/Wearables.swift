//
//  Wearables.swift
//  AmberAI
//
//  The cloud-wearable half of the integration: WHOOP and Oura. Unlike Apple Watch — whose
//  data sits on the phone and is read through HealthKit — these keep the member's data in
//  their own clouds, so each needs the member to connect her own account once. There's no
//  backend here, so the OAuth client secret lives in Config alongside the Runware/OpenAI
//  keys (the same trade-off this app already makes) rather than on a server.
//
//  Both providers speak OAuth 2.0 (authorization-code). Oura also still accepts a legacy
//  Personal Access Token — deprecated by Oura in Dec 2025, but existing tokens work, so we
//  keep that as a shortcut. Everything normalises into the shared WearableSummary that
//  Amber already reads in her prompt.
//

import Foundation
import AuthenticationServices
import UIKit

// MARK: - Errors & tokens

struct WearableError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// One OAuth app's fixed parameters. Built by each provider's Config from the client
/// id/secret the member entered — nil when those aren't set yet.
struct OAuthCredentials {
    let clientId: String
    let clientSecret: String
    let redirectURI: String
    let scope: String
    let authorizeURL: URL
    let tokenURL: URL
    let callbackScheme: String
}

/// The tokens we hold for a connected provider. Persisted per provider in Config.
struct OAuthTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

// MARK: - Small shared helpers

/// Coerce a JSON value that might arrive as Int, Double, NSNumber or String into a Double.
func wearableNum(_ any: Any?) -> Double? {
    switch any {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s)
    default: return nil
    }
}

/// Pull the record array out of a JSON body. Oura wraps rows in "data", WHOOP in "records".
func wearableRecords(_ data: Data, key: String) -> [[String: Any]] {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let arr = obj[key] as? [[String: Any]] else { return [] }
    return arr
}

/// Parse an ISO-8601 timestamp, tolerating fractional seconds either way.
func wearableParseISO(_ string: String?) -> Date? {
    guard let string else { return nil }
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = withFraction.date(from: string) { return d }
    let plain = ISO8601DateFormatter()
    return plain.date(from: string)
}

private func percentEncode(_ s: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
}

/// Authenticated GET returning the raw body, throwing on a non-2xx status.
enum WearableHTTP {
    static func getJSON(_ url: URL, bearer: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WearableError("HTTP \(http.statusCode): \(body.prefix(200))")
        }
        return data
    }
}

// MARK: - OAuth

/// Supplies the window ASWebAuthenticationSession presents its sheet over.
@MainActor
final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresenter()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
        }
        return ASPresentationAnchor()
    }
}

/// The generic OAuth 2.0 authorization-code flow, shared by both cloud providers.
enum OAuth {
    /// Present the provider's sign-in sheet, capture the redirect, and exchange the code.
    @MainActor
    static func authorize(_ creds: OAuthCredentials) async throws -> OAuthTokens {
        guard var comps = URLComponents(url: creds.authorizeURL, resolvingAgainstBaseURL: false) else {
            throw WearableError("Bad authorize URL.")
        }
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: creds.clientId),
            URLQueryItem(name: "redirect_uri", value: creds.redirectURI),
            URLQueryItem(name: "scope", value: creds.scope),
            URLQueryItem(name: "state", value: UUID().uuidString),
        ]
        guard let authURL = comps.url else { throw WearableError("Bad authorize URL.") }

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: authURL, callbackURLScheme: creds.callbackScheme) { url, error in
                if let error { cont.resume(throwing: error) }
                else if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: WearableError("Sign-in returned nothing.")) }
            }
            session.presentationContextProvider = WebAuthPresenter.shared
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                cont.resume(throwing: WearableError("Couldn't start sign-in."))
            }
        }

        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw WearableError("Sign-in was cancelled or denied.")
        }
        return try await exchange(creds, grant: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": creds.redirectURI,
        ])
    }

    /// Swap a refresh token for a fresh access token. WHOOP rotates the refresh token on
    /// every use, so callers must persist whatever comes back.
    static func refresh(_ creds: OAuthCredentials, refreshToken: String) async throws -> OAuthTokens {
        try await exchange(creds, grant: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": creds.scope,
        ])
    }

    private static func exchange(_ creds: OAuthCredentials, grant: [String: String]) async throws -> OAuthTokens {
        var form = grant
        form["client_id"] = creds.clientId
        form["client_secret"] = creds.clientSecret

        var req = URLRequest(url: creds.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\(percentEncode($0.value))" }
            .joined(separator: "&").data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WearableError("Token exchange failed (\(http.statusCode)): \(body.prefix(200))")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String else {
            throw WearableError("No access token in the response.")
        }
        // A refresh response may omit a new refresh token — fall back to the one we sent.
        let refresh = (obj["refresh_token"] as? String) ?? grant["refresh_token"] ?? ""
        let expiresIn = wearableNum(obj["expires_in"]) ?? 3600
        return OAuthTokens(accessToken: access, refreshToken: refresh,
                           expiresAt: Date().addingTimeInterval(expiresIn))
    }
}

// MARK: - Oura

/// Reads a recent snapshot from the Oura Cloud API v2. Auth is a legacy Personal Access
/// Token when present, otherwise the OAuth access token (refreshed as needed).
enum OuraClient {
    private static func bearer() async throws -> String {
        if !OuraConfig.personalToken.isEmpty { return OuraConfig.personalToken }
        guard let creds = OuraConfig.oauth, var tokens = OuraConfig.tokens else {
            throw WearableError("Connect Oura first.")
        }
        if Date() >= tokens.expiresAt.addingTimeInterval(-60) {
            tokens = try await OAuth.refresh(creds, refreshToken: tokens.refreshToken)
            OuraConfig.tokens = tokens
        }
        return tokens.accessToken
    }

    static func summary() async throws -> WearableSummary {
        let token = try await bearer()
        let cal = Calendar.current
        let today = Date()
        let ymd = DateFormatter()
        ymd.dateFormat = "yyyy-MM-dd"
        ymd.timeZone = .current
        let start = ymd.string(from: cal.date(byAdding: .day, value: -7, to: today) ?? today)
        // end_date is exclusive of its own day for some collections, so reach to tomorrow.
        let end = ymd.string(from: cal.date(byAdding: .day, value: 1, to: today) ?? today)

        func rows(_ path: String) async -> [[String: Any]] {
            guard var comps = URLComponents(
                url: OuraConfig.apiBase.appendingPathComponent(path),
                resolvingAgainstBaseURL: false) else { return [] }
            comps.queryItems = [
                URLQueryItem(name: "start_date", value: start),
                URLQueryItem(name: "end_date", value: end),
            ]
            guard let url = comps.url,
                  let data = try? await WearableHTTP.getJSON(url, bearer: token) else { return [] }
            return wearableRecords(data, key: "data")
        }

        var s = WearableSummary(source: .oura)

        let activity = await rows("daily_activity")
        if let steps = activity.last.flatMap({ wearableNum($0["steps"]) }) { s.stepsToday = Int(steps) }
        let allSteps = activity.compactMap { wearableNum($0["steps"]) }
        if !allSteps.isEmpty { s.avgDailySteps = Int((allSteps.reduce(0, +) / Double(allSteps.count)).rounded()) }

        if let sleep = (await rows("sleep")).last {
            if let secs = wearableNum(sleep["total_sleep_duration"]) { s.sleepHoursLastNight = secs / 3600 }
            s.hrvMs = wearableNum(sleep["average_hrv"]).map { Int($0.rounded()) }
            s.restingHeartRate = wearableNum(sleep["lowest_heart_rate"]).map { Int($0.rounded()) }
        }
        if let daily = (await rows("daily_sleep")).last {
            s.sleepScore = wearableNum(daily["score"]).map { Int($0) }
        }
        if let readiness = (await rows("daily_readiness")).last {
            s.readinessScore = wearableNum(readiness["score"]).map { Int($0) }
        }
        let workouts = await rows("workout")
        if !workouts.isEmpty {
            s.workoutsThisWeek = workouts.count
            let minutes = workouts.reduce(0.0) { acc, w in
                guard let a = wearableParseISO(w["start_datetime"] as? String),
                      let b = wearableParseISO(w["end_datetime"] as? String) else { return acc }
                return acc + b.timeIntervalSince(a) / 60
            }
            s.workoutMinutesThisWeek = Int(minutes.rounded())
        }
        return s
    }
}

// MARK: - WHOOP

/// Reads a recent snapshot from the WHOOP API v2. Recovery carries resting HR / HRV /
/// recovery score, the cycle carries day strain, sleep carries performance and duration.
enum WhoopClient {
    private static func bearer() async throws -> String {
        guard let creds = WhoopConfig.oauth, var tokens = WhoopConfig.tokens else {
            throw WearableError("Connect WHOOP first.")
        }
        if Date() >= tokens.expiresAt.addingTimeInterval(-60) {
            tokens = try await OAuth.refresh(creds, refreshToken: tokens.refreshToken)
            WhoopConfig.tokens = tokens   // rotating refresh token — always persist the new one
        }
        return tokens.accessToken
    }

    static func summary() async throws -> WearableSummary {
        let token = try await bearer()

        func records(_ path: String, query: [URLQueryItem] = []) async -> [[String: Any]] {
            guard var comps = URLComponents(
                url: WhoopConfig.apiBase.appendingPathComponent(path),
                resolvingAgainstBaseURL: false) else { return [] }
            var items = query
            items.append(URLQueryItem(name: "limit", value: "10"))
            comps.queryItems = items
            guard let url = comps.url,
                  let data = try? await WearableHTTP.getJSON(url, bearer: token) else { return [] }
            return wearableRecords(data, key: "records")
        }

        var s = WearableSummary(source: .whoop)

        if let score = (await records("v2/recovery")).first?["score"] as? [String: Any] {
            s.restingHeartRate = wearableNum(score["resting_heart_rate"]).map { Int($0.rounded()) }
            s.hrvMs = wearableNum(score["hrv_rmssd_milli"]).map { Int($0.rounded()) }
            s.readinessScore = wearableNum(score["recovery_score"]).map { Int($0) }
        }
        if let score = (await records("v2/cycle")).first?["score"] as? [String: Any] {
            s.strain = wearableNum(score["strain"])
        }
        if let score = (await records("v2/activity/sleep")).first?["score"] as? [String: Any] {
            s.sleepScore = wearableNum(score["sleep_performance_percentage"]).map { Int($0) }
            if let stages = score["stage_summary"] as? [String: Any] {
                let light = wearableNum(stages["total_light_sleep_time_milli"]) ?? 0
                let deep = wearableNum(stages["total_slow_wave_sleep_time_milli"]) ?? 0
                let rem = wearableNum(stages["total_rem_sleep_time_milli"]) ?? 0
                let total = light + deep + rem
                if total > 0 { s.sleepHoursLastNight = total / 3_600_000 }
            }
        }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let startISO = ISO8601DateFormatter().string(from: weekAgo)
        let workouts = await records("v2/activity/workout", query: [URLQueryItem(name: "start", value: startISO)])
        if !workouts.isEmpty {
            s.workoutsThisWeek = workouts.count
            let minutes = workouts.reduce(0.0) { acc, w in
                guard let a = wearableParseISO(w["start"] as? String),
                      let b = wearableParseISO(w["end"] as? String) else { return acc }
                return acc + b.timeIntervalSince(a) / 60
            }
            s.workoutMinutesThisWeek = Int(minutes.rounded())
        }
        // WHOOP does not report a step count.
        return s
    }
}
