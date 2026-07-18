//
//  Account.swift
//  AmberAI
//
//  The account layer a shipping app needs and the demo never had: a real user
//  profile, the eMed membership it belongs to, and a persisted "onboarding done"
//  flag that gates the first run. Kept separate from MemoryState on purpose —
//  memory is the product, the account is who the product belongs to.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Weight-loss context

/// How the member is approaching their weight loss. Drives what Amber and the eMed care
/// team assume about medication and monitoring.
enum ManagementApproach: String, Codable, CaseIterable, Identifiable {
    case lifestyle
    case glp1
    case combination

    var id: String { rawValue }

    /// Tolerant of raw values written before this app switched focus (e.g. an old
    /// "oral" or "insulin" profile), so a stored account still loads.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ManagementApproach(rawValue: raw) ?? .glp1
    }

    var display: String {
        switch self {
        case .lifestyle:   return "Diet and lifestyle"
        case .glp1:        return "GLP-1 medication"
        case .combination: return "A combination"
        }
    }

    var detail: String {
        switch self {
        case .lifestyle:   return "Working on it without prescribed medication for now."
        case .glp1:        return "A weekly injection such as Mounjaro or Wegovy."
        case .combination: return "A GLP-1 alongside diet and lifestyle changes."
        }
    }
}

/// The eMed membership the account is enrolled on. Names mirror how eMed frames its
/// clinician-supported metabolic programme.
enum MembershipPlan: String, Codable, CaseIterable, Identifiable {
    case metabolicCare = "Metabolic Care"
    case glp1Program   = "GLP-1 Programme"
    case monitoring    = "Monitoring Only"

    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .metabolicCare: return "Clinician-supported care, at-home testing and Amber."
        case .glp1Program:   return "GLP-1 prescribing, at-home testing and Amber."
        case .monitoring:    return "At-home testing and Amber, without prescribing."
        }
    }
}

// MARK: - Wearables

/// A wearable or health platform the member can link so Amber and the care team see
/// activity, sleep and recovery alongside weight. Connections persist per account like
/// any other setting. In the demo build linking is simulated — no third-party OAuth —
/// but the model, storage and UI are shaped for the real integrations to drop in.
enum Wearable: String, Codable, CaseIterable, Identifiable {
    case appleWatch = "Apple Watch"
    case whoop      = "WHOOP"
    case oura       = "Oura Ring"
    case garmin     = "Garmin"

    var id: String { rawValue }

    /// SF Symbol used in the connect list.
    var icon: String {
        switch self {
        case .appleWatch: return "applewatch"
        case .whoop:      return "bolt.heart"
        case .oura:       return "circle.circle"
        case .garmin:     return "figure.outdoor.cycle"
        }
    }

    /// One-line description of what linking this device shares.
    var detail: String {
        switch self {
        case .appleWatch: return "Steps, heart rate, workouts and sleep via Apple Health."
        case .whoop:      return "Strain, recovery and sleep from your WHOOP band."
        case .oura:       return "Sleep, readiness and heart-rate variability from your Oura ring."
        case .garmin:     return "Activity, workouts and sleep from your Garmin device."
        }
    }
}

// MARK: - Profile

/// The signed-in member. Everything here is entered by the person during onboarding
/// or edited later in Settings — nothing is inferred.
struct UserProfile: Codable, Hashable {
    var firstName: String = ""
    var lastName: String = ""
    var email: String = ""

    // Weight-loss context.
    var management: ManagementApproach = .glp1
    var medication: String = ""
    /// 0 = Sunday … 6 = Saturday. nil when there is no weekly injection.
    var injectionDay: Int? = nil
    /// Her starting weight and where she is aiming, in kilograms. Both optional — she
    /// may prefer not to set a target. These anchor the trend on the Progress tab.
    var startWeightKg: Double? = nil
    var goalWeightKg: Double? = nil

    // eMed membership.
    var plan: MembershipPlan = .metabolicCare
    var memberId: String = ""
    var prescriber: String = ""
    /// Opt-in to eMed's at-home blood test kit (onboarding, 6 and 12 months).
    var homeTestOptIn: Bool = true

    // Preferences.
    var checkInReminders: Bool = true

    /// Wearables the member has linked. Optional so accounts saved before this feature
    /// existed still decode (a missing key reads as nil, i.e. nothing connected).
    var connectedWearables: Set<Wearable>? = nil

    var fullName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var initials: String {
        let a = firstName.first.map(String.init) ?? ""
        let b = lastName.first.map(String.init) ?? ""
        let joined = (a + b)
        return joined.isEmpty ? "?" : joined.uppercased()
    }

    /// Prefilled with the seeded demo patient so the account layer and the seeded
    /// memory tell the same story out of the box. Onboarding overwrites it.
    static var demo: UserProfile {
        UserProfile(
            firstName: Patient.firstName, lastName: "Puchkov",
            email: "kirill.puchkov@example.com",
            management: .glp1,
            medication: Patient.medication, injectionDay: 0,
            startWeightKg: 95.4, goalWeightKg: 78,
            plan: .glp1Program, memberId: "EM-4021-7788",
            prescriber: Patient.prescriber, homeTestOptIn: true,
            checkInReminders: true)
    }
}

extension Int {
    /// Weekday name for an injection-day index where 0 = Sunday.
    var weekdayName: String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return names.indices.contains(self) ? names[self] : "—"
    }
}

// MARK: - Store

/// Owns the profile and the first-run flag, persists both, and models sign-out /
/// delete-account so Settings can behave like a shipping app.
@MainActor
final class AccountStore: ObservableObject {
    @Published var profile: UserProfile
    @Published private(set) var onboardingComplete: Bool

    private let fileURL: URL
    private let onboardingKey = "amber_onboarding_complete"

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("amber-account.json")

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = loaded
        } else {
            profile = .demo
        }
        onboardingComplete = UserDefaults.standard.bool(forKey: onboardingKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profile) {
            try? data.write(to: fileURL)
        }
    }

    /// Save any edits made in Settings.
    func save(_ profile: UserProfile) {
        self.profile = profile
        persist()
    }

    /// Link or unlink a wearable, persisting the change.
    func setWearable(_ wearable: Wearable, connected: Bool) {
        var linked = profile.connectedWearables ?? []
        if connected { linked.insert(wearable) } else { linked.remove(wearable) }
        profile.connectedWearables = linked
        persist()
    }

    /// Land the onboarding answers and open the app.
    func completeOnboarding(with profile: UserProfile) {
        self.profile = profile
        persist()
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }

    /// Sign out returns to the onboarding / sign-in flow but keeps the profile on
    /// disk so signing back in is prefilled.
    func signOut() {
        onboardingComplete = false
        UserDefaults.standard.set(false, forKey: onboardingKey)
    }

    /// Erase the member entirely and return to a clean first run.
    func deleteAccount() {
        try? FileManager.default.removeItem(at: fileURL)
        profile = UserProfile()
        onboardingComplete = false
        UserDefaults.standard.set(false, forKey: onboardingKey)
    }
}
