//
//  HealthStore.swift
//  AmberAI
//
//  The wearable layer. Apple Watch is read on-device through HealthKit; WHOOP and Oura are
//  read from their clouds (see Wearables.swift). Every provider normalises into one
//  WearableSummary, and WearableStore keeps the connected ones in sync so Amber can carry
//  them in her context alongside weight and food. Read-only everywhere — Amber never
//  writes to any of them.
//

import Foundation
import HealthKit
import Combine

// MARK: - Normalised snapshot

/// A compact, recent snapshot from a single wearable. A value type so it can sit on
/// AppState and be read wherever the prompt is built. Every field is optional — a given
/// device reports only some of these, and the member may not wear it to bed, and so on.
struct WearableSummary: Equatable {
    let source: Wearable

    var stepsToday: Int?
    var avgDailySteps: Int?         // over the last 7 days
    var restingHeartRate: Int?      // most recent, bpm
    var hrvMs: Int?                 // most recent, ms
    var sleepHoursLastNight: Double?
    var sleepScore: Int?            // 0–100 (Oura daily sleep / WHOOP sleep performance)
    var readinessScore: Int?        // 0–100 (Oura readiness / WHOOP recovery)
    var strain: Double?             // WHOOP day strain, 0–21
    var workoutsThisWeek: Int?
    var workoutMinutesThisWeek: Int?

    init(source: Wearable) { self.source = source }

    /// True when at least one metric came back.
    var hasAnything: Bool {
        stepsToday != nil || avgDailySteps != nil || restingHeartRate != nil ||
        hrvMs != nil || sleepHoursLastNight != nil || sleepScore != nil ||
        readinessScore != nil || strain != nil || (workoutsThisWeek ?? 0) > 0
    }

    /// A one-line preview for the Settings row.
    var shortLine: String? {
        guard hasAnything else { return nil }
        var bits: [String] = []
        if let s = stepsToday { bits.append("\(s.formatted()) steps") }
        if let sl = sleepHoursLastNight { bits.append(String(format: "%.1f h sleep", sl)) }
        if let r = readinessScore { bits.append("\(r)% ready") }
        if let r = restingHeartRate, bits.count < 3 { bits.append("\(r) bpm resting") }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    /// The metric lines for the prompt, one per available field.
    var promptLines: [String] {
        var lines: [String] = []
        if let s = stepsToday { lines.append("Steps today: \(s)") }
        if let a = avgDailySteps { lines.append("Average daily steps (last 7 days): \(a)") }
        if let sl = sleepHoursLastNight { lines.append(String(format: "Sleep last night: %.1f h", sl)) }
        if let sc = sleepScore { lines.append("Sleep score: \(sc)/100") }
        if let rd = readinessScore {
            let label = source == .whoop ? "Recovery" : "Readiness"
            lines.append("\(label): \(rd)/100")
        }
        if let st = strain { lines.append(String(format: "Day strain: %.1f/21", st)) }
        if let r = restingHeartRate { lines.append("Resting heart rate: \(r) bpm") }
        if let h = hrvMs { lines.append("Heart-rate variability: \(h) ms") }
        if let w = workoutsThisWeek, w > 0 {
            lines.append("Workouts this week: \(w) (\(workoutMinutesThisWeek ?? 0) min total)")
        }
        return lines
    }
}

/// Fold every connected wearable's snapshot into one instruction block, or nil when there's
/// nothing to say (so buildInstructions skips the section rather than print an empty header).
func wearablesPromptBlock(_ summaries: [WearableSummary]) -> String? {
    let live = summaries.filter { $0.hasAnything }
    guard !live.isEmpty else { return nil }
    var out = ["HER WEARABLES (read just now)"]
    for summary in live {
        out.append("\(summary.source.rawValue):")
        out.append(contentsOf: summary.promptLines.map { "- \($0)" })
    }
    out.append("Use this to ground your coaching — a poor night's sleep, a big step day, a low")
    out.append("recovery, a quiet week of workouts — but weave it in naturally. Do not read the")
    out.append("numbers back like a dashboard, and never present them as medical advice.")
    return out.joined(separator: "\n")
}

// MARK: - Store

/// Owns every wearable connection and the latest snapshots. One @MainActor ObservableObject
/// the views hold as an environment object, mirroring AccountStore's shape.
@MainActor
final class WearableStore: ObservableObject {
    /// Latest snapshot per connected wearable.
    @Published private(set) var summaries: [Wearable: WearableSummary] = [:]
    /// Wearables with a fetch in flight, so each row can show its own progress.
    @Published private(set) var working: Set<Wearable> = []
    /// Last error surfaced to the member, else nil.
    @Published var lastError: String?

    private let hk = HKHealthStore()

    /// Snapshots in a stable order, for the prompt and any UI list.
    var allSummaries: [WearableSummary] { Wearable.allCases.compactMap { summaries[$0] } }

    func isWorking(_ wearable: Wearable) -> Bool { working.contains(wearable) }

    /// Whether HealthKit exists on this device at all (false on iPad and some simulators).
    var healthKitAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Whether a given wearable can be connected right now (has what it needs to auth).
    func canConnect(_ wearable: Wearable) -> Bool {
        switch wearable {
        case .appleWatch: return healthKitAvailable
        case .oura:       return OuraConfig.isConfigured
        case .whoop:      return WhoopConfig.isConfigured
        case .garmin:     return false
        }
    }

    // MARK: Connect / disconnect

    /// Run the wearable's auth step (permission sheet or OAuth), then pull a first snapshot.
    /// Returns true once the member is authenticated and a snapshot came back.
    func connect(_ wearable: Wearable) async -> Bool {
        working.insert(wearable)
        defer { working.remove(wearable) }
        do {
            switch wearable {
            case .appleWatch:
                guard healthKitAvailable else {
                    throw WearableError("Health data isn't available on this device.")
                }
                try await hk.requestAuthorization(toShare: [], read: healthKitReadTypes)

            case .oura:
                if OuraConfig.personalToken.isEmpty && OuraConfig.tokens == nil {
                    guard let creds = OuraConfig.oauth else {
                        throw WearableError("Add your Oura token or OAuth credentials in Advanced.")
                    }
                    OuraConfig.tokens = try await OAuth.authorize(creds)
                }

            case .whoop:
                if WhoopConfig.tokens == nil {
                    guard let creds = WhoopConfig.oauth else {
                        throw WearableError("Add your WHOOP client ID and secret in Advanced.")
                    }
                    WhoopConfig.tokens = try await OAuth.authorize(creds)
                }

            case .garmin:
                throw WearableError("Garmin isn't available yet.")
            }

            summaries[wearable] = try await fetchSummary(wearable)
            return true
        } catch {
            lastError = (error as? WearableError)?.message ?? error.localizedDescription
            return false
        }
    }

    /// Stop reading a wearable and drop it from Amber's context. HealthKit permission can't
    /// be revoked in code; OAuth tokens are cleared so the next connect signs in fresh.
    func disconnect(_ wearable: Wearable) {
        summaries[wearable] = nil
        switch wearable {
        case .oura:  OuraConfig.tokens = nil
        case .whoop: WhoopConfig.tokens = nil
        default:     break
        }
    }

    // MARK: Refresh

    /// Re-read one wearable's snapshot. Best-effort: a failure leaves the last snapshot.
    func refresh(_ wearable: Wearable) async {
        working.insert(wearable)
        defer { working.remove(wearable) }
        do {
            summaries[wearable] = try await fetchSummary(wearable)
        } catch {
            lastError = (error as? WearableError)?.message ?? error.localizedDescription
        }
    }

    /// Re-read every connected wearable, concurrently.
    func refreshAll(_ connected: Set<Wearable>) async {
        await withTaskGroup(of: Void.self) { group in
            for wearable in connected {
                group.addTask { await self.refresh(wearable) }
            }
        }
    }

    private func fetchSummary(_ wearable: Wearable) async throws -> WearableSummary {
        switch wearable {
        case .appleWatch: return await appleWatchSummary()
        case .oura:       return try await OuraClient.summary()
        case .whoop:      return try await WhoopClient.summary()
        case .garmin:     throw WearableError("Garmin isn't available yet.")
        }
    }

    // MARK: - Apple Watch (HealthKit)

    private var healthKitReadTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.activeEnergyBurned),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
        ]
    }

    /// Build the Apple Watch snapshot from HealthKit. Best-effort per metric.
    private func appleWatchSummary() async -> WearableSummary {
        async let steps = stepsToday()
        async let avg = averageDailySteps()
        async let rhr = mostRecentQuantity(.restingHeartRate,
                                           unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrv = mostRecentQuantity(.heartRateVariabilitySDNN,
                                           unit: .secondUnit(with: .milli))
        async let sleep = sleepHoursLastNight()
        async let workouts = workoutsThisWeek()

        var s = WearableSummary(source: .appleWatch)
        s.stepsToday = await steps
        s.avgDailySteps = await avg
        s.restingHeartRate = (await rhr).map { Int($0.rounded()) }
        s.hrvMs = (await hrv).map { Int($0.rounded()) }
        s.sleepHoursLastNight = await sleep
        let (count, minutes) = await workouts
        s.workoutsThisWeek = count
        s.workoutMinutesThisWeek = minutes
        return s
    }

    private func startOfToday() -> Date { Calendar.current.startOfDay(for: Date()) }

    private func stepsSum(from start: Date, to end: Date) async -> Double? {
        let predicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(.stepCount),
            predicate: HKQuery.predicateForSamples(withStart: start, end: end))
        let descriptor = HKStatisticsQueryDescriptor(predicate: predicate, options: .cumulativeSum)
        guard let stats = try? await descriptor.result(for: hk) else { return nil }
        return stats.sumQuantity()?.doubleValue(for: .count())
    }

    private func stepsToday() async -> Int? {
        (await stepsSum(from: startOfToday(), to: Date())).map { Int($0.rounded()) }
    }

    private func averageDailySteps() async -> Int? {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: startOfToday()) ?? startOfToday()
        guard let total = await stepsSum(from: start, to: Date()) else { return nil }
        return Int((total / 7).rounded())
    }

    private func mostRecentQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let predicate = HKSamplePredicate.quantitySample(type: HKQuantityType(id), predicate: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        let samples = try? await descriptor.result(for: hk)
        return samples?.first?.quantity.doubleValue(for: unit)
    }

    /// Hours asleep over roughly the last night — sums asleep segments in the last 24h.
    private func sleepHoursLastNight() async -> Double? {
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
        let predicate = HKSamplePredicate.categorySample(
            type: HKCategoryType(.sleepAnalysis),
            predicate: HKQuery.predicateForSamples(withStart: start, end: Date()))
        let descriptor = HKSampleQueryDescriptor(predicates: [predicate], sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await descriptor.result(for: hk), !samples.isEmpty else { return nil }

        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues
        let seconds = samples.reduce(0.0) { total, sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value),
                  asleep.contains(value) else { return total }
            return total + sample.endDate.timeIntervalSince(sample.startDate)
        }
        return seconds > 0 ? seconds / 3600 : nil
    }

    /// Count and total minutes of workouts in the last 7 days.
    private func workoutsThisWeek() async -> (Int?, Int?) {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKSamplePredicate.workout(HKQuery.predicateForSamples(withStart: start, end: Date()))
        let descriptor = HKSampleQueryDescriptor(predicates: [predicate], sortDescriptors: [SortDescriptor(\.startDate)])
        guard let workouts = try? await descriptor.result(for: hk), !workouts.isEmpty else { return (nil, nil) }
        let minutes = workouts.reduce(0.0) { $0 + $1.duration } / 60
        return (workouts.count, Int(minutes.rounded()))
    }
}
