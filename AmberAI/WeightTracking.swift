//
//  WeightTracking.swift
//  AmberAI
//
//  Weight maths. Pure, no model, mirroring Food.swift: everything is indexed by
//  programme week + day so a weigh-in scrubs with `app.week` exactly like a fact or a
//  meal does. The trend never asserts anything — it only reads back what he logged.
//

import Foundation

/// Next `w-NNN` id, mirroring nextFoodId's scheme.
func nextWeightId(_ entries: [WeightEntry]) -> String {
    let nums = entries.compactMap { Int($0.id.replacingOccurrences(of: "w-", with: "")) }
    return "w-" + String(format: "%03d", (nums.max() ?? 0) + 1)
}

/// Time filter, newest first. Display, mirroring foodAsOf.
func weightAsOf(_ entries: [WeightEntry], _ week: Int) -> [WeightEntry] {
    entries
        .filter { $0.week <= week }
        .sorted { a, b in
            if a.week != b.week { return a.week > b.week }
            return a.day > b.day
        }
}

/// Chronological series (oldest → newest) up to `week`, for the trend chart.
func weightSeries(_ entries: [WeightEntry], _ week: Int) -> [WeightEntry] {
    entries
        .filter { $0.week <= week }
        .sorted { a, b in
            if a.week != b.week { return a.week < b.week }
            return a.day < b.day
        }
}

/// The most recent weigh-in at or before `week`.
func latestWeight(_ entries: [WeightEntry], _ week: Int) -> WeightEntry? {
    weightAsOf(entries, week).first
}

/// The earliest weigh-in on record at or before `week` — his starting point.
func firstWeight(_ entries: [WeightEntry], _ week: Int) -> WeightEntry? {
    weightSeries(entries, week).first
}

/// The single weigh-in logged on a specific day, if any.
func weightForDay(_ entries: [WeightEntry], _ week: Int, _ day: Int) -> WeightEntry? {
    entries.first { $0.week == week && $0.day == day }
}

/// A flat day index across the programme, so weigh-ins from different weeks line up on
/// one axis in the chart and sort correctly.
func programmeDay(week: Int, day: Int) -> Int { (week - 1) * 7 + day }

/// What Amber is told about his weight. His own logged numbers, read straight back —
/// start, latest, the net change, and the last few weigh-ins. Like the food block it
/// states nothing: a companion who remembers the numbers, not a coach who grades them.
func weightForPrompt(_ entries: [WeightEntry], _ week: Int) -> String {
    let series = weightSeries(entries, week)
    guard let latest = series.last else { return "" }

    var lines: [String] = []
    if let first = series.first, first.id != latest.id {
        let delta = latest.kg - first.kg
        let dir = delta < 0 ? "down" : (delta > 0 ? "up" : "level")
        lines.append("He started at \(fmtKg(first.kg)) kg (week \(first.week)) and last weighed \(fmtKg(latest.kg)) kg (week \(latest.week)) — \(dir) \(fmtKg(abs(delta))) kg overall.")
    } else {
        lines.append("His only weigh-in on record is \(fmtKg(latest.kg)) kg (week \(latest.week)).")
    }

    let recent = series.suffix(4)
    if recent.count > 1 {
        let trail = recent.map { "week \($0.week): \(fmtKg($0.kg)) kg" }.joined(separator: ", ")
        lines.append("Recent weigh-ins — \(trail).")
    }

    return """
    What he has weighed recently:
    \(lines.joined(separator: "\n"))

    These are his own numbers. Read one back if it helps his, but do not grade them, do \
    not call a change good, bad, fast, slow, on track or behind, and never set a target \
    weight or a pace. Whether the trend is right is between him and his prescriber. If he \
    is doing the maths on himself, you can gently remind his that is not yours to weigh in on.
    """
}

private func fmtKg(_ d: Double) -> String {
    d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
}
