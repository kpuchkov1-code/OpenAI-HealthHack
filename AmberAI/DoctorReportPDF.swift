//
//  DoctorReportPDF.swift
//  AmberAI
//
//  The treatment hand-off, rendered as a properly laid-out PDF in Amber's own palette
//  rather than a wall of monospaced text. It draws on everything the app legitimately
//  holds about his treatment — weight, nutrition, the habits he set, his connected
//  wearables, the symptoms and instructions on record, and the records themselves — and
//  keeps the app's one rule: it reads the numbers straight back and never grades them.
//  Interpreting any of it is a clinical act, left to his care team.
//
//  Like `DoctorReport` (the plain-text sibling this replaces in the UI), it deliberately
//  leaves out the personal things he has told Amber in chat — the whippet, the fear of
//  needles, the low weeks. Those are his, not his doctor's; only `.medication`,
//  `.clinicalInstruction` and `.symptom` facts ever reach the page. Everything is gated
//  to the current programme week, so the report scrubs honestly with the rest of the app.
//

import UIKit
import SwiftUI
import PDFKit

// MARK: - Brand palette (UIColor mirrors of Theme, for CoreGraphics drawing)

private enum PDFTheme {
    static let amber     = UIColor(red: 0.85, green: 0.61, blue: 0.13, alpha: 1)
    static let amberSoft = UIColor(red: 0.90, green: 0.78, blue: 0.50, alpha: 1)
    static let bg        = UIColor(red: 0.995, green: 0.985, blue: 0.965, alpha: 1)
    static let ink       = UIColor(red: 0.16, green: 0.13, blue: 0.11, alpha: 1)
    static let muted     = UIColor(red: 0.42, green: 0.40, blue: 0.37, alpha: 1)
    static let support   = UIColor(red: 0.80, green: 0.30, blue: 0.24, alpha: 1)
    static let steady    = UIColor(red: 0.30, green: 0.55, blue: 0.36, alpha: 1)
    static let zebra     = UIColor(red: 0.98, green: 0.95, blue: 0.88, alpha: 1)
}

// MARK: - Public entry point

enum DoctorReportPDF {
    /// Render the whole report to a PDF on disk and return its URL, or nil if writing
    /// failed. Gated to `week` and fed the live wearable snapshots so the page matches
    /// exactly what the rest of the app can see right now.
    static func render(state: MemoryState, week: Int, profile: UserProfile,
                       wearables: [WearableSummary]) -> URL? {
        let name = profile.fullName.isEmpty ? Patient.name : profile.fullName
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .long
        let dateStr = dateFmt.string(from: Date())
        let weekLabel = SEED_TIMELINE.first { $0.week == week }?.label ?? "Week \(week)"

        // A4 at 72 dpi.
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { rctx in
            let canvas = ReportCanvas(ctx: rctx, page: pageRect, patientName: name)
            canvas.startPage(running: false)
            canvas.cover(week: week, weekLabel: weekLabel, dateStr: dateStr)
            buildBody(canvas, state: state, week: week, profile: profile,
                      wearables: wearables, name: name, weekLabel: weekLabel, dateStr: dateStr)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Amber-report.pdf")
        do { try data.write(to: url); return url } catch { return nil }
    }

    // MARK: - Body

    private static func buildBody(_ c: ReportCanvas, state: MemoryState, week: Int,
                                  profile: UserProfile, wearables: [WearableSummary],
                                  name: String, weekLabel: String, dateStr: String) {
        // Clinical facts only — the same gate `DoctorReport` uses. Personal and struggle
        // facts never appear here, by their absence from `clinicalTypes`.
        let clinicalFacts = state.facts.filter {
            $0.forgotten != true && $0.weekLearned <= week && DoctorReport.clinicalTypes.contains($0.type)
        }
        let series = weightSeries(state.weightEntries, week)
        let latest = series.last
        let start = profile.startWeightKg ?? series.first?.kg
        let liveWearables = wearables.filter { $0.hasAnything }

        // MARK: Patient & programme
        c.section("Patient & programme")
        c.field("Name", name)
        c.field("Age", "\(Patient.age)")
        if !profile.memberId.isEmpty { c.field("eMed member ID", profile.memberId) }
        c.field("Membership", profile.plan.rawValue)
        c.field("Approach", profile.management.display)
        if !profile.medication.isEmpty { c.field("Medication", profile.medication) }
        if let day = profile.injectionDay { c.field("Weekly injection", day.weekdayName) }
        if !profile.prescriber.isEmpty { c.field("Prescriber", profile.prescriber) }
        c.field("Programme week", "\(week) — \(weekLabel)")
        c.field("Report prepared", dateStr)

        // MARK: Overview
        c.section("How he is doing")
        for line in overview(name: name, week: week, profile: profile, series: series,
                             latest: latest, start: start, state: state,
                             clinicalFacts: clinicalFacts, liveWearables: liveWearables) {
            c.paragraph(line)
        }

        // MARK: Weight
        c.section("Weight")
        if let latest {
            if let start {
                c.field("Starting weight", "\(foodNum(start)) kg")
                let delta = latest.kg - start
                let dir = delta < 0 ? "down" : (delta > 0 ? "up" : "level")
                c.field("Latest weigh-in", "\(foodNum(latest.kg)) kg (week \(latest.week))")
                c.field("Net change", delta == 0 ? "No change overall" : "\(dir) \(foodNum(abs(delta))) kg overall")
            } else {
                c.field("Latest weigh-in", "\(foodNum(latest.kg)) kg (week \(latest.week))")
            }
            if let goal = profile.goalWeightKg { c.field("Goal weight", "\(foodNum(goal)) kg") }

            let recent = series.suffix(8)
            if recent.count > 1 {
                c.gap(6)
                c.table(["Week", "Day", "Weight", "Note"],
                        recent.reversed().map { e in
                            ["\(e.week)", "\(e.day + 1)", "\(foodNum(e.kg)) kg", e.note ?? "—"]
                        },
                        weights: [0.8, 0.8, 1.1, 2.3], numeric: [0, 1, 2])
            }
        } else {
            c.paragraph("No weigh-ins logged yet.")
            if let goal = profile.goalWeightKg { c.field("Goal weight", "\(foodNum(goal)) kg") }
        }

        // MARK: Nutrition
        c.section("Nutrition trends")
        let loggedWeeks = Set(state.foodEntries.filter { $0.week <= week }.map { $0.week }).sorted()
        if loggedWeeks.isEmpty {
            c.paragraph("No meals logged.")
        } else {
            c.paragraph("Counts of what he logged, per week. Only days he logged appear; an unlogged day is left blank rather than counted as zero.")
            let rows: [[String]] = loggedWeeks.suffix(8).map { w in
                let entries = state.foodEntries.filter { $0.week == w }
                let daysLogged = Set(entries.map { $0.day }).count
                let protein = entries.reduce(0.0) { $0 + ($1.nutrition?.proteinG ?? 0) }
                let perDay = (protein > 0 && daysLogged > 0) ? "\(foodNum(protein / Double(daysLogged))) g" : "—"
                return ["\(w)", "\(entries.count)", "\(daysLogged)", perDay]
            }
            c.table(["Week", "Meals", "Days logged", "Protein / logged day"],
                    rows, weights: [0.8, 1, 1.2, 1.8], numeric: [0, 1, 2, 3])
        }

        // MARK: Habits
        c.section("Habits he set for himself")
        let habits = activeHabits(state.habits, week)
        if habits.isEmpty {
            c.paragraph("No habits set yet.")
        } else {
            let onTrack = habits.filter { habitWeek($0, state.checkIns, week, state.foodEntries).met }.count
            c.paragraph("He is keeping \(habits.count) habit\(habits.count == 1 ? "" : "s"); \(onTrack) \(onTrack == 1 ? "is" : "are") on track this week. These are aims he chose, not prescriptions.")
            let rows: [[String]] = habits.map { h in
                let hw = habitWeek(h, state.checkIns, week, state.foodEntries)
                let aim = h.direction == .atMost ? "≤ \(h.target)/wk" : "\(h.target)/wk"
                let status: String
                if h.direction == .atMost { status = hw.met ? "Within limit" : "Over limit" }
                else { status = hw.met ? "On track" : "Under" }
                return [h.label, scheduleLabel(h), aim, "\(hw.count)", status]
            }
            c.table(["Habit", "Days", "Aim", "This week", "Status"],
                    rows, weights: [2.1, 1.2, 0.9, 1, 1.1], numeric: [3])

            // The weeks-at-a-glance strip: how many habits met their aim each recent week.
            let firstWeek = max(1, week - 7)
            if week > firstWeek {
                c.gap(4)
                c.subheading("Weekly adherence")
                let arows: [[String]] = (firstWeek...week).map { w in
                    let a = weekAdherence(state.habits, state.checkIns, w, state.foodEntries)
                    return ["Week \(w)", a.total > 0 ? "\(a.met) of \(a.total) met" : "No habits set"]
                }
                c.table(["", "Habits met"], arows, weights: [1, 2], numeric: [])
            }
        }

        // MARK: Wearables
        c.section("Activity, sleep & recovery")
        if liveWearables.isEmpty {
            c.paragraph("No wearable was connected, or none returned data, when this report was prepared. Apple Watch, Oura and WHOOP can be linked in the app to include steps, sleep, heart rate and recovery here.")
        } else {
            c.paragraph("Read live from his connected devices when this report was prepared — a recent snapshot, not a continuous record.")
            for summary in liveWearables {
                c.subheading(summary.source.rawValue, color: PDFTheme.amber)
                for (label, value) in wearableFields(summary) {
                    c.field(label, value)
                }
            }
        }

        // MARK: Symptoms
        c.section("Symptoms he has reported")
        let symptoms = clinicalFacts.filter { $0.type == .symptom }.sorted { $0.weekLearned < $1.weekLearned }
        if symptoms.isEmpty {
            c.paragraph("No symptoms recorded.")
        } else {
            c.paragraph("In his own words, transcribed never interpreted. No symptom here has been judged mild, severe or concerning — that is for his clinician.")
            for f in symptoms {
                c.bullet(f.content, sub: "\(source(f.source)) · week \(f.weekLearned)",
                         dotColor: FactType.symptom.tintUIColor)
            }
        }

        // MARK: Medication & instructions
        c.section("Medication & clinical instructions")
        let meds = clinicalFacts.filter { $0.type == .medication }.sorted { $0.weekLearned < $1.weekLearned }
        let instructions = clinicalFacts.filter { $0.type == .clinicalInstruction }.sorted { $0.weekLearned < $1.weekLearned }
        if meds.isEmpty && instructions.isEmpty {
            c.paragraph("Nothing clinical recorded yet.")
        } else {
            if !meds.isEmpty {
                c.subheading("Medication")
                for f in meds {
                    c.bullet(f.content, sub: "\(source(f.source)) · week \(f.weekLearned)",
                             dotColor: FactType.medication.tintUIColor)
                }
            }
            if !instructions.isEmpty {
                c.subheading("Clinical instructions")
                for f in instructions {
                    c.bullet(f.content, sub: "\(source(f.source)) · week \(f.weekLearned)",
                             dotColor: FactType.clinicalInstruction.tintUIColor)
                }
            }
        }

        // MARK: Records on file
        c.section("Records on file")
        let docs = state.documents.filter { $0.uploadedWeek <= week }
        if docs.isEmpty {
            c.paragraph("No records uploaded.")
        } else {
            c.table(["Record", "Type", "Week", "Results"],
                    docs.map { d in
                        [d.name, kindLabel(d.kind), "\(d.uploadedWeek)", "\(d.factIds.count)"]
                    },
                    weights: [2.6, 1.2, 0.7, 0.9], numeric: [2, 3])

            // Amber's own short brief of each record read end-to-end, gated to when it
            // arrived. Transcribed, not interpreted — the same contract as the facts.
            let digests = state.digests.filter { $0.createdWeek <= week }
            if !digests.isEmpty {
                c.gap(4)
                c.subheading("What Amber read in each record")
                for d in digests {
                    c.bullet(d.content, sub: d.sourceLabel)
                }
            }
        }

        // MARK: Closing note
        c.section("About this report")
        c.paragraph("This report covers his treatment only. The personal things he has shared with Amber in conversation — why he started, how he has felt on the hard weeks — are deliberately left out.")
        c.paragraph("Every figure is either logged by him, read live from a connected wearable, or transcribed from a record. Nothing here has been graded, ranked, or interpreted. Whether any of it is on track is between him and his care team.",
                    font: c.smallFont, color: PDFTheme.muted)
    }

    // MARK: - Overview text

    private static func overview(name: String, week: Int, profile: UserProfile,
                                 series: [WeightEntry], latest: WeightEntry?, start: Double?,
                                 state: MemoryState, clinicalFacts: [MemoryFact],
                                 liveWearables: [WearableSummary]) -> [String] {
        var lines: [String] = []

        var opening = "\(name) is in week \(week) of an eMed \(profile.plan.rawValue.lowercased())"
        if !profile.medication.isEmpty { opening += ", using \(profile.medication)" }
        if let day = profile.injectionDay { opening += " with a weekly injection on \(day.weekdayName)" }
        opening += "."
        lines.append(opening)

        if let latest, let start {
            let delta = latest.kg - start
            var s = "His logged weight has moved from \(foodNum(start)) kg to \(foodNum(latest.kg)) kg"
            if delta == 0 { s += " — unchanged since starting" }
            else { s += " — \(delta < 0 ? "down" : "up") \(foodNum(abs(delta))) kg since starting" }
            if let goal = profile.goalWeightKg { s += ", against a goal of \(foodNum(goal)) kg" }
            s += "."
            lines.append(s)
        } else if let latest {
            lines.append("His most recent logged weight is \(foodNum(latest.kg)) kg.")
        }

        let meals = state.foodEntries.filter { $0.week <= week }
        let weeksLogged = Set(meals.map { $0.week }).count
        if !meals.isEmpty {
            lines.append("He has logged \(meals.count) meal\(meals.count == 1 ? "" : "s") across \(weeksLogged) week\(weeksLogged == 1 ? "" : "s").")
        }

        let habits = activeHabits(state.habits, week)
        if !habits.isEmpty {
            let onTrack = habits.filter { habitWeek($0, state.checkIns, week, state.foodEntries).met }.count
            lines.append("He is keeping \(habits.count) habit\(habits.count == 1 ? "" : "s") he set himself; \(onTrack) \(onTrack == 1 ? "is" : "are") on track this week.")
        }

        if !liveWearables.isEmpty {
            let names = liveWearables.map { $0.source.rawValue }.joined(separator: ", ")
            lines.append("His connected wearable\(liveWearables.count == 1 ? "" : "s") (\(names)) \(liveWearables.count == 1 ? "was" : "were") read for this report; the latest figures are in the activity section below.")
        }

        let symptomCount = clinicalFacts.filter { $0.type == .symptom }.count
        if symptomCount > 0 {
            lines.append("He has reported \(symptomCount) symptom\(symptomCount == 1 ? "" : "s") to Amber, listed below in his own words.")
        }

        return lines
    }

    // MARK: - Small helpers

    /// Label/value pairs for one wearable snapshot, matching how the app names each metric.
    private static func wearableFields(_ s: WearableSummary) -> [(String, String)] {
        var f: [(String, String)] = []
        if let v = s.stepsToday { f.append(("Steps today", v.formatted())) }
        if let v = s.avgDailySteps { f.append(("Avg daily steps (7 days)", v.formatted())) }
        if let v = s.sleepHoursLastNight { f.append(("Sleep last night", String(format: "%.1f h", v))) }
        if let v = s.sleepScore { f.append(("Sleep score", "\(v) / 100")) }
        if let v = s.readinessScore { f.append((s.source == .whoop ? "Recovery" : "Readiness", "\(v) / 100")) }
        if let v = s.strain { f.append(("Day strain", String(format: "%.1f / 21", v))) }
        if let v = s.restingHeartRate { f.append(("Resting heart rate", "\(v) bpm")) }
        if let v = s.hrvMs { f.append(("Heart-rate variability", "\(v) ms")) }
        if let w = s.workoutsThisWeek, w > 0 {
            f.append(("Workouts this week", "\(w) (\(s.workoutMinutesThisWeek ?? 0) min total)"))
        }
        return f
    }

    private static func source(_ src: FactSource) -> String {
        switch src {
        case .conversation:  return "reported by him"
        case .consult:       return "Dr Patel consult"
        case .document:      return "from a record"
        case .habit:         return "from a habit"
        case .consolidated:  return "summarised"
        }
    }

    private static func kindLabel(_ kind: DocumentKind) -> String {
        switch kind {
        case .bloodPanel:   return "Blood panel"
        case .letter:       return "Letter"
        case .prescription: return "Prescription"
        case .other:        return "Record"
        }
    }
}

private extension FactType {
    /// The UIColor mirror of the SwiftUI `tint`, so fact bullets carry the same colour
    /// coding the Memory screen uses.
    var tintUIColor: UIColor {
        switch self {
        case .symptom:            return UIColor(red: 0.35, green: 0.52, blue: 0.72, alpha: 1)
        case .medication:         return UIColor(red: 0.55, green: 0.40, blue: 0.70, alpha: 1)
        case .clinicalInstruction:return UIColor(red: 0.30, green: 0.55, blue: 0.50, alpha: 1)
        case .personal:           return PDFTheme.amber
        case .struggle:           return PDFTheme.support
        }
    }
}

// MARK: - The drawing canvas

/// A tiny top-to-bottom layout engine over a PDF context. Everything flows down from `y`,
/// paginating as it goes, with a branded footer on every page and a running header on
/// continuation pages. Kept deliberately small: headings, paragraphs, key/value fields,
/// bullet lists and simple zebra tables cover the whole report.
private final class ReportCanvas {
    private let ctx: UIGraphicsPDFRendererContext
    private let page: CGRect
    private let patientName: String
    private let margin: CGFloat = 48
    private let footerReserve: CGFloat = 46
    private var y: CGFloat = 0
    private var pageNumber = 0

    let smallFont = UIFont.systemFont(ofSize: 9)
    private let bodyFont = UIFont.systemFont(ofSize: 10.5)

    private var contentWidth: CGFloat { page.width - margin * 2 }

    init(ctx: UIGraphicsPDFRendererContext, page: CGRect, patientName: String) {
        self.ctx = ctx
        self.page = page
        self.patientName = patientName
    }

    // MARK: Pages

    func startPage(running: Bool) {
        ctx.beginPage()
        pageNumber += 1
        fill(page, PDFTheme.bg)
        drawFooter()
        if running {
            draw("Amber — report for \(patientName)’s care team",
                 at: CGPoint(x: margin, y: margin - 6),
                 font: .systemFont(ofSize: 8.5, weight: .semibold), color: PDFTheme.muted,
                 maxWidth: contentWidth)
            fill(CGRect(x: margin, y: margin + 8, width: contentWidth, height: 0.75), PDFTheme.amberSoft)
            y = margin + 18
        } else {
            y = margin
        }
    }

    private func drawFooter() {
        let fy = page.height - 32
        fill(CGRect(x: margin, y: fy, width: contentWidth, height: 0.75), PDFTheme.amberSoft)
        draw("Confidential · Generated by Amber for \(patientName)’s care team",
             at: CGPoint(x: margin, y: fy + 6), font: .systemFont(ofSize: 8),
             color: PDFTheme.muted, maxWidth: contentWidth - 90)
        draw("Page \(pageNumber)", at: CGPoint(x: page.width - margin - 90, y: fy + 6),
             font: .systemFont(ofSize: 8), color: PDFTheme.muted, maxWidth: 90, align: .right)
    }

    /// The branded band across the top of the first page.
    func cover(week: Int, weekLabel: String, dateStr: String) {
        let bandH: CGFloat = 112
        fill(CGRect(x: 0, y: 0, width: page.width, height: bandH), PDFTheme.amber)
        draw("Amber", at: CGPoint(x: margin, y: 30),
             font: .systemFont(ofSize: 32, weight: .heavy), color: .white, maxWidth: 320)
        draw("Report for your care team", at: CGPoint(x: margin, y: 74),
             font: .systemFont(ofSize: 13, weight: .medium),
             color: UIColor.white.withAlphaComponent(0.92), maxWidth: 320)
        let rx = page.width - margin - 240
        draw("Programme week \(week)", at: CGPoint(x: rx, y: 34),
             font: .systemFont(ofSize: 12, weight: .semibold), color: .white, maxWidth: 240, align: .right)
        draw(weekLabel, at: CGPoint(x: rx, y: 52),
             font: .systemFont(ofSize: 10), color: UIColor.white.withAlphaComponent(0.9),
             maxWidth: 240, align: .right)
        draw("Prepared \(dateStr)", at: CGPoint(x: rx, y: 74),
             font: .systemFont(ofSize: 10), color: UIColor.white.withAlphaComponent(0.9),
             maxWidth: 240, align: .right)
        y = bandH + 22
    }

    // MARK: Blocks

    func gap(_ h: CGFloat) { y += h }

    func section(_ title: String) {
        y += 14
        ensure(50)
        draw(title.uppercased(), at: CGPoint(x: margin, y: y),
             font: .systemFont(ofSize: 12.5, weight: .heavy), color: PDFTheme.amber, maxWidth: contentWidth)
        y += 19
        fill(CGRect(x: margin, y: y, width: contentWidth, height: 1.5), PDFTheme.amberSoft)
        y += 10
    }

    func subheading(_ text: String, color: UIColor = PDFTheme.ink) {
        y += 4
        ensure(22)
        draw(text, at: CGPoint(x: margin, y: y),
             font: .systemFont(ofSize: 11, weight: .bold), color: color, maxWidth: contentWidth)
        y += 17
    }

    func paragraph(_ text: String, font: UIFont? = nil, color: UIColor = PDFTheme.ink, gap: CGFloat = 7) {
        let f = font ?? bodyFont
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2.5
        let attr = NSAttributedString(string: text,
                                      attributes: [.font: f, .foregroundColor: color, .paragraphStyle: para])
        let h = measure(attr, width: contentWidth)
        ensure(h)
        attr.draw(with: CGRect(x: margin, y: y, width: contentWidth, height: h + 2),
                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        y += h + gap
    }

    func field(_ label: String, _ value: String) {
        let leftW: CGFloat = 150
        let colGap: CGFloat = 12
        let rightW = contentWidth - leftW - colGap
        let lFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let vFont = UIFont.systemFont(ofSize: 10.5)
        let lh = measure(label, font: lFont, width: leftW)
        let vh = measure(value, font: vFont, width: rightW)
        let h = max(lh, vh)
        ensure(h + 4)
        draw(label, at: CGPoint(x: margin, y: y), font: lFont, color: PDFTheme.muted, maxWidth: leftW)
        draw(value, at: CGPoint(x: margin + leftW + colGap, y: y), font: vFont, color: PDFTheme.ink, maxWidth: rightW)
        y += h + 5
    }

    func bullet(_ content: String, sub: String? = nil, dotColor: UIColor = PDFTheme.amber) {
        let font = UIFont.systemFont(ofSize: 10.5)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2.5
        para.headIndent = 14
        para.firstLineHeadIndent = 14
        let attr = NSAttributedString(string: content,
                                      attributes: [.font: font, .foregroundColor: PDFTheme.ink, .paragraphStyle: para])
        let h = measure(attr, width: contentWidth)
        var subH: CGFloat = 0
        var subAttr: NSAttributedString?
        if let sub {
            let sp = NSMutableParagraphStyle()
            sp.headIndent = 14
            sp.firstLineHeadIndent = 14
            let sa = NSAttributedString(string: sub,
                                        attributes: [.font: smallFont, .foregroundColor: PDFTheme.muted, .paragraphStyle: sp])
            subAttr = sa
            subH = measure(sa, width: contentWidth)
        }
        ensure(h + subH + 6)
        fill(CGRect(x: margin + 3, y: y + 5, width: 4, height: 4), dotColor, ellipse: true)
        attr.draw(with: CGRect(x: margin, y: y, width: contentWidth, height: h + 2),
                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        y += h + 2
        if let subAttr {
            subAttr.draw(with: CGRect(x: margin, y: y, width: contentWidth, height: subH + 2),
                         options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            y += subH + 4
        } else {
            y += 3
        }
    }

    /// A simple zebra-striped table. `weights` are relative column widths; `numeric`
    /// columns are right-aligned. Redraws its header row after a page break.
    func table(_ headers: [String], _ rows: [[String]], weights: [CGFloat], numeric: Set<Int> = []) {
        let sum = weights.reduce(0, +)
        let widths = weights.map { contentWidth * $0 / max(sum, 0.0001) }
        var xs: [CGFloat] = []
        var acc = margin
        for w in widths { xs.append(acc); acc += w }
        let padH: CGFloat = 7
        let padV: CGFloat = 5
        let headFont = UIFont.systemFont(ofSize: 9.5, weight: .bold)
        let cellFont = UIFont.systemFont(ofSize: 9.5)

        func drawHeader() {
            let h: CGFloat = 22
            ensure(h + 22)
            fill(CGRect(x: margin, y: y, width: contentWidth, height: h), PDFTheme.amber)
            for (i, head) in headers.enumerated() where i < widths.count {
                let align: NSTextAlignment = numeric.contains(i) ? .right : .left
                draw(head, at: CGPoint(x: xs[i] + padH, y: y + padV + 1), font: headFont,
                     color: .white, maxWidth: widths[i] - padH * 2, align: align)
            }
            y += h
        }

        drawHeader()
        var zebra = false
        for row in rows {
            var rowH: CGFloat = 0
            for (i, cell) in row.enumerated() where i < widths.count {
                rowH = max(rowH, measure(cell, font: cellFont, width: widths[i] - padH * 2))
            }
            rowH = max(rowH + padV * 2, 20)
            if y + rowH > page.height - footerReserve {
                startPage(running: true)
                drawHeader()
                zebra = false
            }
            if zebra { fill(CGRect(x: margin, y: y, width: contentWidth, height: rowH), PDFTheme.zebra) }
            for (i, cell) in row.enumerated() where i < widths.count {
                let align: NSTextAlignment = numeric.contains(i) ? .right : .left
                draw(cell, at: CGPoint(x: xs[i] + padH, y: y + padV), font: cellFont,
                     color: PDFTheme.ink, maxWidth: widths[i] - padH * 2, align: align)
            }
            y += rowH
            zebra.toggle()
        }
        fill(CGRect(x: margin, y: y, width: contentWidth, height: 0.75), PDFTheme.amberSoft)
        y += 8
    }

    // MARK: Primitives

    private func ensure(_ h: CGFloat) {
        if y + h > page.height - footerReserve { startPage(running: true) }
    }

    private func fill(_ rect: CGRect, _ color: UIColor, ellipse: Bool = false) {
        ctx.cgContext.setFillColor(color.cgColor)
        if ellipse { ctx.cgContext.fillEllipse(in: rect) } else { ctx.cgContext.fill(rect) }
    }

    /// Draw a single flowing block at an absolute origin (does not advance `y`).
    private func draw(_ s: String, at p: CGPoint, font: UIFont, color: UIColor,
                      maxWidth: CGFloat, align: NSTextAlignment = .left) {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        para.lineSpacing = 2
        para.lineBreakMode = .byWordWrapping
        let attr = NSAttributedString(string: s,
                                      attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
        attr.draw(with: CGRect(x: p.x, y: p.y, width: maxWidth, height: 1000),
                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    private func measure(_ s: String, font: UIFont, width: CGFloat) -> CGFloat {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        return measure(NSAttributedString(string: s, attributes: [.font: font, .paragraphStyle: para]), width: width)
    }

    private func measure(_ attr: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(attr.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }
}

// MARK: - Preview

/// A read-only PDFKit view so the member can see the finished report before sharing it.
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = UIColor(Theme.bg)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
