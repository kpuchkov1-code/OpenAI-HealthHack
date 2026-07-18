//
//  Food.swift
//  AmberAI
//
//  Food maths and the food-to-symptom link. Pure, no model. Everything returns facts
//  and their ids, never a verdict, so the prompt has nothing to quote except his own
//  words. Ported from lib/food.ts.
//

import Foundation

/// Two data points is not a pattern. Weeks 1-2 are exempt from correlation.
let CORRELATION_FROM_WEEK = 3

/// Time filter, mirroring factsAsOf. Display.
func foodAsOf(_ entries: [FoodEntry], _ week: Int) -> [FoodEntry] {
    entries
        .filter { $0.week <= week }
        .sorted { a, b in
            if a.week != b.week { return a.week > b.week }
            return a.day > b.day
        }
}

/// Symptom facts already linked to this meal. Re-checks `forgotten` so a tombstoned
/// fact stops appearing beside the food too.
func linkedSymptoms(_ entry: FoodEntry, _ facts: [MemoryFact], _ week: Int) -> [MemoryFact] {
    if week < CORRELATION_FROM_WEEK { return [] }
    return facts.filter { f in
        f.type == .symptom && f.forgotten != true && entry.linkedFactIds.contains(f.id)
    }
}

/// Grams of protein logged on a given day of a given week. Sums only what a source stated.
func proteinForDay(_ entries: [FoodEntry], _ week: Int, _ day: Int) -> Double {
    entries
        .filter { $0.week == week && $0.day == day }
        .reduce(0) { $0 + ($1.nutrition?.proteinG ?? 0) }
}

/// Days in the week he met a protein floor, derived from what he logged rather than
/// from a box he ticked.
func daysMeetingProtein(_ entries: [FoodEntry], _ week: Int, _ floorG: Double) -> [Int] {
    (0..<7).filter { proteinForDay(entries, week, $0) >= floorG }
}

/// What Amber is told about his food. Goes through factsForPrompt for the symptom side
/// so consent applies. Phrased as observations, never as a cause.
func foodForPrompt(_ state: MemoryState, _ week: Int) -> String {
    let entries = foodAsOf(state.foodEntries, week).filter { $0.week >= week - 3 }
    if entries.isEmpty { return "" }

    let usable = factsForPrompt(state.facts, week, state.consent)
    let usableIds = Set(usable.map { $0.id })

    let lines = entries.prefix(12).map { e -> String in
        let said = e.linkedFactIds
            .filter { usableIds.contains($0) }
            .compactMap { id in usable.first { $0.id == id } }
            .map { "\"\($0.content)\"" }
        let hedge = e.estimated == true ? " (estimated from a photo, not a label)" : ""
        let protein = e.nutrition?.proteinG != nil ? ", \(fmt(e.nutrition!.proteinG!))g protein" : ""
        let after = said.isEmpty ? "" : " Afterwards he told you: \(said.joined(separator: "; "))."
        return "  - Week \(e.week), day \(e.day + 1): \(e.label)\(protein)\(hedge).\(after)"
    }

    return """
    What he has logged eating recently:
    \(lines.joined(separator: "\n"))

    Use this only to remember, never to judge. You may tell his what he ate before and \
    what he told you happened afterwards, in his words. You must NOT tell his a food \
    caused a symptom, that a food is bad, good, safe, risky, or to be avoided, and you \
    must not add up his calories at his. If he asks you whether a food is causing \
    something, say plainly that you only know what he has told you happened before, \
    tell his that, and leave the conclusion to his and his prescriber.

    He stopped logging meals once already because it made his feel marked. Do not \
    mention the log unless it is genuinely useful to his in the moment.
    """
}

private func fmt(_ d: Double) -> String {
    d == d.rounded() ? String(Int(d)) : String(d)
}

// MARK: - Daily nutrition report

/// Daily nutrition goals behind the calendar's day report. On a clinician-guided GLP-1
/// weight-loss week these are deliberately modest, with protein kept high to protect
/// muscle while losing weight. A single shared target for the demo; not yet surfaced in
/// onboarding, so kept as a constant rather than on the profile.
struct NutritionTargets {
    var kcal: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fibreG: Double

    static let programme = NutritionTargets(kcal: 1500, proteinG: 100, carbsG: 150, fatG: 50, fibreG: 30)
}

/// One day of food added up: the portion macros logged, how many meals they came from,
/// and how many label-only entries (per-100 g, no portion) had to be left out. Summing
/// per-100 g values would invent a number he never stated, so those are counted, not added.
struct DayNutrition {
    var kcal: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var fibreG: Double = 0
    /// Meals whose macros were per-serving and so contribute to the totals above.
    var mealCount: Int = 0
    /// Meals stored per 100 g (a label), excluded from the totals so nothing is invented.
    var labelOnlyCount: Int = 0

    var hasTotals: Bool { mealCount > 0 && kcal > 0 }
}

/// Adds up one (week, day) from the food log. Only per-serving entries contribute to the
/// totals; per-100 g label entries are counted separately so the report never sums a
/// portion he never stated.
func dayNutrition(_ entries: [FoodEntry], week: Int, day: Int) -> DayNutrition {
    var out = DayNutrition()
    for e in entries where e.week == week && e.day == day {
        guard let n = e.nutrition else { continue }
        if n.basis == "per_serving" {
            out.mealCount += 1
            out.kcal += n.kcal ?? 0
            out.proteinG += n.proteinG ?? 0
            out.carbsG += n.carbsG ?? 0
            out.fatG += n.fatG ?? 0
            out.fibreG += n.fibreG ?? 0
        } else {
            out.labelOnlyCount += 1
        }
    }
    return out
}
