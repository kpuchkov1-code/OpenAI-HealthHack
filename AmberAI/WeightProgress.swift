//
//  WeightProgress.swift
//  AmberAI
//
//  The weight-loss surface that sits at the top of Habits: where she is now against
//  where she started, a trend she can scrub through time, and a calendar of her
//  programme. The calendar is honest to the app's clock — rows are programme weeks,
//  columns are Monday-first days — so tapping a day shows exactly what that (week, day)
//  holds: the weigh-in and the meals she logged.
//

import SwiftUI
import Charts

/// A (week, day) the calendar can hand to a summary sheet.
struct DayRef: Identifiable, Hashable {
    let week: Int
    let day: Int
    var id: String { "\(week)-\(day)" }
}

/// The weight-loss surface, embedded at the top of the Habits tab. Owns its own weigh-in
/// and day-summary sheets; reads the shared `app.week`, so it scrubs in step with Habits.
struct WeightProgressSection: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var account: AccountStore

    @State private var showWeightLog = false
    @State private var selectedDay: DayRef?

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(spacing: 16) {
            weightCard
            trendCard
            logWeightButton
            calendarCard
        }
        .sheet(isPresented: $showWeightLog) {
            WeightLogView().environmentObject(app)
        }
        .sheet(item: $selectedDay) { ref in
            DaySummarySheet(ref: ref).environmentObject(app)
        }
    }

    // MARK: - Weight summary

    private var startWeight: Double? {
        account.profile.startWeightKg ?? firstWeight(app.state.weightEntries, app.week)?.kg
    }

    private var weightCard: some View {
        let current = app.currentWeight
        let start = startWeight
        let goal = account.profile.goalWeightKg
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current weight").font(.caption).foregroundStyle(.secondary)
                    if let current {
                        Text("\(foodNum(current.kg)) kg")
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.ink)
                    } else {
                        Text("Not logged yet")
                            .font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let current, let start {
                    changeTag(from: start, to: current.kg)
                }
            }

            if let start, let goal, let current {
                goalBar(start: start, goal: goal, current: current.kg)
            }
        }
        .cardBackground()
    }

    /// Loss shows as a calm win; a gain is stated plainly, never scolded.
    private func changeTag(from start: Double, to now: Double) -> some View {
        let delta = now - start
        let down = delta <= 0
        let text = "\(down ? "−" : "+")\(foodNum(abs(delta))) kg"
        return VStack(alignment: .trailing, spacing: 2) {
            Tag(text: text, color: down ? Theme.steady : Theme.watch)
            Text("since the start").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func goalBar(start: Double, goal: Double, current: Double) -> some View {
        // Fraction of the way from start to goal, clamped to 0…1.
        let span = start - goal
        let progressed = start - current
        let frac = span > 0 ? max(0, min(1, progressed / span)) : 0
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.amberSoft.opacity(0.4))
                    Capsule().fill(Theme.amber).frame(width: geo.size.width * frac)
                }
            }
            .frame(height: 8)
            HStack {
                Text("Start \(foodNum(start)) kg").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("Goal \(foodNum(goal)) kg").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// The trend in its own card, given room to breathe. The y-axis is pinned to the
    /// data's own range (not zero, and not stretched down to the goal), so a few
    /// kilograms of change read as a clear slope instead of a flat line pinned to the top.
    private var trendCard: some View {
        let series = weightSeries(app.state.weightEntries, app.week)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Weight trend").font(.headline)
            if series.count >= 2 {
                trendChart(series)
            } else {
                Text("Log a couple of weigh-ins and your trend appears here.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            }
        }
        .cardBackground()
    }

    private func trendChart(_ series: [WeightEntry]) -> some View {
        // Pad the domain a little above and below the logged range so the line sits in
        // the middle of the card rather than skimming an edge.
        let kgs = series.map { $0.kg }
        let lo = (kgs.min() ?? 0) - 0.6
        let hi = (kgs.max() ?? 1) + 0.6
        return Chart {
            ForEach(series) { e in
                let x = programmeDay(week: e.week, day: e.day)
                AreaMark(
                    x: .value("Day", x),
                    yStart: .value("kg", lo),
                    yEnd: .value("kg", e.kg))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.amber.opacity(0.22), Theme.amber.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
                LineMark(
                    x: .value("Day", x),
                    y: .value("kg", e.kg))
                .foregroundStyle(Theme.amber)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("Day", x),
                    y: .value("kg", e.kg))
                .foregroundStyle(.white)
                .symbolSize(28)
                PointMark(
                    x: .value("Day", x),
                    y: .value("kg", e.kg))
                .foregroundStyle(Theme.amber)
                .symbolSize(14)
            }
        }
        .chartYScale(domain: lo...hi)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.amberSoft.opacity(0.3))
                AxisValueLabel {
                    if let kg = value.as(Double.self) {
                        Text("\(foodNum(kg))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: 7)) { value in
                AxisValueLabel {
                    if let day = value.as(Int.self) {
                        Text("W\(day / 7 + 1)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 170)
    }

    private var logWeightButton: some View {
        Button {
            showWeightLog = true
        } label: {
            Label("Log weight", systemImage: "scalemass")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.amber, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your programme").font(.headline)
                Text("Tap a day to see what you logged.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Weekday header, aligned to the day columns (leading column is the week label).
            HStack(spacing: 6) {
                Text("").frame(width: 34)
                ForEach(0..<7, id: \.self) { d in
                    Text(dayLabels[d])
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.amber)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 6) {
                ForEach(Array(stride(from: app.minWeek, through: app.week, by: 1)), id: \.self) { w in
                    weekRow(w)
                }
            }

            legend
        }
        .cardBackground()
    }

    /// One programme week. The current week gets a soft amber band so "now" is obvious.
    private func weekRow(_ week: Int) -> some View {
        let isCurrent = week == app.week
        return HStack(spacing: 6) {
            Text("W\(week)")
                .font(.caption.weight(.bold))
                .foregroundStyle(isCurrent ? Theme.amber : .secondary)
                .frame(width: 34, alignment: .leading)
            ForEach(0..<7, id: \.self) { d in
                dayCell(week: week, day: d)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrent ? Theme.amber.opacity(0.06) : .clear)
        )
    }

    private func dayCell(week: Int, day: Int) -> some View {
        let hasWeight = weightForDay(app.state.weightEntries, week, day) != nil
        let hasFood = app.state.foodEntries.contains { $0.week == week && $0.day == day }
        let anything = hasWeight || hasFood
        return Button {
            selectedDay = DayRef(week: week, day: day)
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(hasWeight ? Theme.amber : Color.clear)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Theme.amberSoft.opacity(hasWeight ? 0 : 0.7), lineWidth: 1))
                Circle()
                    .fill(hasFood ? Theme.steady : Color.clear)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Theme.steady.opacity(hasFood ? 0 : 0.35), lineWidth: 1))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(anything ? Theme.amber.opacity(0.12) : Color(white: 0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(anything ? Theme.amber.opacity(0.35) : Theme.amberSoft.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Circle().fill(Theme.amber).frame(width: 7, height: 7)
                Text("Weigh-in").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                Circle().fill(Theme.steady).frame(width: 7, height: 7)
                Text("Food logged").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Day summary

/// A one-day nutrition report for a single (week, day): the calories and macros she
/// logged read against her daily targets, then the meals they came from. The totals live
/// here, in a view she taps into on purpose — not in Amber's voice, which still follows
/// Food.swift's rule never to add her calories up at her unprompted.
private struct DaySummarySheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let ref: DayRef

    private let targets = NutritionTargets.programme

    var body: some View {
        NavigationStack {
            List {
                nutritionSection

                if let w = weightForDay(app.state.weightEntries, ref.week, ref.day) {
                    Section("Weight") {
                        LabeledContent("Weighed in", value: "\(foodNum(w.kg)) kg")
                        if let note = w.note, !note.isEmpty {
                            Text(note).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }

                Section(meals.isEmpty ? "Meals" : "Meals (\(meals.count))") {
                    if meals.isEmpty {
                        Text("No meals logged this day.").foregroundStyle(.secondary)
                    } else {
                        ForEach(meals) { entry in mealRow(entry) }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.amber)
    }

    private var meals: [FoodEntry] {
        app.state.foodEntries
            .filter { $0.week == ref.week && $0.day == ref.day }
    }

    private var title: String {
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let dayName = names.indices.contains(ref.day) ? names[ref.day] : "Day \(ref.day + 1)"
        return "Week \(ref.week) · \(dayName)"
    }

    // MARK: Nutrition report

    private var day: DayNutrition {
        dayNutrition(app.state.foodEntries, week: ref.week, day: ref.day)
    }

    @ViewBuilder private var nutritionSection: some View {
        let d = day
        Section {
            if d.hasTotals {
                calorieSummary(d)
                    .listRowSeparator(.hidden)
                macroBar("Protein", value: d.proteinG, target: targets.proteinG, color: Theme.amber)
                macroBar("Carbs", value: d.carbsG, target: targets.carbsG, color: Theme.steady)
                macroBar("Fat", value: d.fatG, target: targets.fatG, color: Theme.watch)
                macroBar("Fibre", value: d.fibreG, target: targets.fibreG, color: Theme.support)
            } else {
                Text(d.labelOnlyCount > 0
                     ? "The meals here came from labels (per 100 g), so there's no portion total to add up."
                     : "Nothing with nutrition logged this day.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } header: {
            Text("Nutrition")
        } footer: {
            if d.hasTotals { Text(footnote(d)) }
        }
    }

    /// The calorie headline: what she got against her target, a fill bar that turns to the
    /// support colour when she is over, and a plain over/under/on-target read.
    private func calorieSummary(_ d: DayNutrition) -> some View {
        let frac = targets.kcal > 0 ? d.kcal / targets.kcal : 0
        let over = d.kcal > targets.kcal * 1.05
        let barColor = over ? Theme.support : Theme.amber
        let status = calorieStatus(d)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(foodNum(d.kcal))")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text("/ \(foodNum(targets.kcal)) kcal")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Tag(text: status.text, color: status.color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(barColor.opacity(0.15))
                    Capsule().fill(barColor)
                        .frame(width: geo.size.width * min(max(frac, 0), 1))
                }
            }
            .frame(height: 10)
            Text("\(Int((frac * 100).rounded()))% of your daily calories, from \(d.mealCount) meal\(d.mealCount == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func calorieStatus(_ d: DayNutrition) -> (text: String, color: Color) {
        let diff = d.kcal - targets.kcal
        if d.kcal > targets.kcal * 1.05 {
            return ("Over by \(foodNum(diff)) kcal", Theme.support)
        } else if d.kcal < targets.kcal * 0.85 {
            return ("\(foodNum(-diff)) under", Theme.watch)
        } else {
            return ("On target", Theme.steady)
        }
    }

    private func macroBar(_ name: String, value: Double, target: Double, color: Color) -> some View {
        let frac = target > 0 ? min(value / target, 1) : 0
        let over = target > 0 && value > target * 1.1
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(foodNum(value)) / \(foodNum(target)) g")
                    .font(.caption).foregroundStyle(over ? Theme.support : .secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule().fill(color).frame(width: geo.size.width * frac)
                }
            }
            .frame(height: 7)
        }
        .padding(.vertical, 2)
    }

    /// A gentle one-liner under the report: what went well, and an honest note when some
    /// label-only meals could not be counted toward the total.
    private func footnote(_ d: DayNutrition) -> String {
        var parts: [String] = []
        if d.proteinG >= targets.proteinG {
            parts.append("Protein target met — good for holding on to muscle.")
        }
        if d.labelOnlyCount > 0 {
            parts.append("\(d.labelOnlyCount) label-only meal\(d.labelOnlyCount == 1 ? "" : "s") isn't in the total.")
        }
        return parts.isEmpty ? "Added up from the portions you logged." : parts.joined(separator: " ")
    }

    private func mealRow(_ entry: FoodEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.label).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
            if let sub = nutritionLine(entry.nutrition) {
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            if entry.estimated == true {
                Label("Amber's estimate, not a label.", systemImage: "sparkles")
                    .font(.caption2).foregroundStyle(Theme.amber)
            }
            if let note = entry.note, !note.isEmpty {
                Text("“\(note)”").font(.caption.italic()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// A per-meal line, values as stored — no cross-meal totals.
    private func nutritionLine(_ n: FoodNutrition?) -> String? {
        guard let n else { return nil }
        var bits: [String] = []
        if let kcal = n.kcal { bits.append("\(foodNum(kcal)) kcal") }
        if let p = n.proteinG { bits.append("\(foodNum(p)) g protein") }
        guard !bits.isEmpty else { return nil }
        let basis = n.basis == "per_100g" ? " / 100 g" : ""
        return bits.joined(separator: " · ") + basis
    }
}
