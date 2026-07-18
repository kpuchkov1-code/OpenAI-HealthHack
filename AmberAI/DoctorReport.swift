//
//  DoctorReport.swift
//  AmberAI
//
//  A report the patient can hand to his prescriber. Pure, no model: it assembles only
//  the treatment-facing record — his weight, his nutrition trends, and the clinical
//  facts (medication, symptoms, clinical instructions) alongside the records already
//  transcribed. It deliberately leaves out the personal things he has told Amber in
//  chat — why he started, the whippet, the fear of needles. Those are his, not his
//  doctor's. Like the rest of the app it reads numbers straight back from what he
//  logged or a lab printed; it never grades a value or infers a cause.
//

import Foundation

enum DoctorReport {
    /// The fact types that belong in a clinical hand-off, in the order they are printed.
    /// `.personal` and `.struggle` — the confidences he shares with Amber — are excluded
    /// by their absence here, which is the whole point of the report.
    static let clinicalTypes: [FactType] = [.medication, .clinicalInstruction, .symptom]

    /// Build the whole report as plain text, gated to `week` so it scrubs honestly with
    /// the rest of the app: nothing learned or logged after the current week appears.
    static func build(state: MemoryState, week: Int, profile: UserProfile) -> String {
        var s: [String] = []

        s.append(contentsOf: header(profile: profile, week: week))
        s.append("")
        s.append(contentsOf: weightSection(state, week, profile))
        s.append("")
        s.append(contentsOf: nutritionSection(state, week))
        s.append("")
        s.append(contentsOf: treatmentSection(state, week))
        s.append("")
        s.append(contentsOf: recordsSection(state, week))
        s.append("")
        s.append("——")
        s.append("This report covers his treatment only. The personal things he has shared "
               + "with Amber in conversation are deliberately left out.")

        return s.joined(separator: "\n")
    }

    // MARK: - Sections

    private static func header(profile: UserProfile, week: Int) -> [String] {
        let name = profile.fullName.isEmpty ? Patient.name : profile.fullName
        var lines = ["AMBER — REPORT FOR YOUR CARE TEAM", "Prepared at programme week \(week)", ""]
        lines.append("Patient: \(name), age \(Patient.age)")
        if !profile.medication.isEmpty { lines.append("Medication: \(profile.medication)") }
        if let day = profile.injectionDay { lines.append("Weekly injection: \(day.weekdayName)") }
        if !profile.prescriber.isEmpty { lines.append("Prescriber: \(profile.prescriber)") }
        return lines
    }

    private static func weightSection(_ state: MemoryState, _ week: Int, _ profile: UserProfile) -> [String] {
        var lines = ["WEIGHT"]
        let series = weightSeries(state.weightEntries, week)
        // His stated starting weight anchors the trend if he set one; otherwise fall
        // back to the earliest weigh-in on record, exactly like the Progress tab.
        let start = profile.startWeightKg ?? series.first?.kg

        guard let latest = series.last else {
            lines.append("No weigh-ins logged yet.")
            if let goal = profile.goalWeightKg { lines.append("Goal weight: \(foodNum(goal)) kg") }
            return lines
        }

        if let start {
            lines.append("Starting weight: \(foodNum(start)) kg")
            let delta = latest.kg - start
            let dir = delta < 0 ? "down" : (delta > 0 ? "up" : "level")
            lines.append("Latest weigh-in: \(foodNum(latest.kg)) kg (week \(latest.week))")
            if delta == 0 {
                lines.append("Net change: no change overall")
            } else {
                lines.append("Net change: \(dir) \(foodNum(abs(delta))) kg overall")
            }
        } else {
            lines.append("Latest weigh-in: \(foodNum(latest.kg)) kg (week \(latest.week))")
        }
        if let goal = profile.goalWeightKg { lines.append("Goal weight: \(foodNum(goal)) kg") }

        let recent = series.suffix(6)
        if recent.count > 1 {
            lines.append("Recent weigh-ins:")
            for e in recent {
                lines.append("  · week \(e.week), day \(e.day + 1): \(foodNum(e.kg)) kg")
            }
        }
        return lines
    }

    private static func nutritionSection(_ state: MemoryState, _ week: Int) -> [String] {
        var lines = ["NUTRITION TRENDS"]
        // Only weeks he actually logged appear; a blank week is left blank rather than
        // implied to be zero. Trends are per-week counts and protein — never a calorie
        // total added up at his, in keeping with the food log's rule.
        let weeks = Set(state.foodEntries.filter { $0.week <= week }.map { $0.week }).sorted()
        guard !weeks.isEmpty else {
            lines.append("No meals logged.")
            return lines
        }

        lines.append("Only days he logged are shown; unlogged days are blank.")
        for w in weeks.suffix(8) {
            let entries = state.foodEntries.filter { $0.week == w }
            let daysLogged = Set(entries.map { $0.day }).count
            let totalProtein = entries.reduce(0.0) { $0 + ($1.nutrition?.proteinG ?? 0) }
            let mealWord = entries.count == 1 ? "meal" : "meals"
            let dayWord = daysLogged == 1 ? "day" : "days"
            var line = "  · Week \(w): \(entries.count) \(mealWord) across \(daysLogged) \(dayWord)"
            if totalProtein > 0 && daysLogged > 0 {
                line += ", ~\(foodNum(totalProtein / Double(daysLogged))) g protein per logged day"
            }
            lines.append(line)
        }
        return lines
    }

    private static func treatmentSection(_ state: MemoryState, _ week: Int) -> [String] {
        var lines = ["TREATMENT NOTES"]
        lines.append("From his records, consults and check-ins — in his own words, never interpreted.")

        // Clinical facts only, tombstones removed, gated to the current week. Personal and
        // struggle facts never reach this list.
        let facts = state.facts.filter { f in
            f.forgotten != true && f.weekLearned <= week && clinicalTypes.contains(f.type)
        }
        guard !facts.isEmpty else {
            lines.append("Nothing clinical recorded yet.")
            return lines
        }

        for type in clinicalTypes {
            let group = facts.filter { $0.type == type }.sorted { $0.weekLearned < $1.weekLearned }
            guard !group.isEmpty else { continue }
            lines.append("")
            lines.append(heading(type) + ":")
            for f in group {
                lines.append("  · \(f.content) (\(source(f.source)), week \(f.weekLearned))")
            }
        }
        return lines
    }

    private static func recordsSection(_ state: MemoryState, _ week: Int) -> [String] {
        var lines = ["RECORDS ON FILE"]
        let docs = state.documents.filter { $0.uploadedWeek <= week }
        guard !docs.isEmpty else {
            lines.append("No records uploaded.")
            return lines
        }
        for doc in docs {
            let n = doc.factIds.count
            let resultWord = n == 1 ? "result" : "results"
            lines.append("  · \(doc.name) (week \(doc.uploadedWeek)) — \(n) \(resultWord) transcribed")
        }
        return lines
    }

    // MARK: - Labels

    private static func heading(_ type: FactType) -> String {
        switch type {
        case .medication: return "Medication"
        case .clinicalInstruction: return "Clinical instructions"
        case .symptom: return "Symptoms reported"
        case .personal, .struggle: return type.display  // never reached; kept exhaustive
        }
    }

    /// A short provenance tag for a fact, so the doctor can see where each note came from.
    private static func source(_ src: FactSource) -> String {
        switch src {
        case .conversation: return "reported by him"
        case .consult: return "Dr Patel consult"
        case .document: return "from a record"
        case .habit: return "from a habit"
        case .consolidated: return "summarised"
        }
    }
}
