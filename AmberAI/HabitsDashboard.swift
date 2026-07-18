//
//  HabitsDashboard.swift
//  AmberAI
//
//  The whole Habits screen, in one card. It answers three questions without a streak
//  count: how many of her habits are on track this week, how the trend has gone over an
//  adjustable time frame — always at one-day resolution, so zooming out widens the window
//  rather than coarsening a day into a week — and, as a compact table, where each habit
//  stands today with a single tick box to mark it off. The trend bars are tappable: a tap
//  opens exactly which habits she did and didn't do for that day. Rest days (a habit's
//  unscheduled days) are left out of the maths, so a day off never reads as a miss. All of
//  it reads the same `app.week` and the same habit maths the prompt uses, so it scrubs
//  honestly with time.
//

import SwiftUI

struct HabitsDashboardCard: View {
    @EnvironmentObject var app: AppState
    let habits: [Habit]

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    /// How much history the trend bars cover. Every option keeps a one-bar-per-day grain —
    /// zooming out widens the window, it never coarsens a day into a week.
    enum Timeframe: String, CaseIterable, Identifiable {
        case week = "This week"
        case fourWeeks = "4 weeks"
        case eightWeeks = "8 weeks"
        var id: String { rawValue }
        var weeks: Int {
            switch self {
            case .week: return 1
            case .fourWeeks: return 4
            case .eightWeeks: return 8
            }
        }
    }

    /// Which bar she tapped, so the detail sheet knows what breakdown to show.
    enum ChartSelection: Identifiable {
        case day(week: Int, day: Int)
        case week(Int)
        var id: String {
            switch self {
            case .day(let w, let d): return "d-\(w)-\(d)"
            case .week(let w): return "w-\(w)"
            }
        }
    }

    @State private var timeframe: Timeframe = .week
    @State private var selection: ChartSelection?

    /// The week for every active habit, computed once and shared by the ring and checklist.
    private var weeks: [HabitWeek] {
        habits.map { habitWeek($0, app.state.checkIns, app.week, app.state.foodEntries) }
    }

    /// Habits holding to their aim this week, respecting direction.
    private var onTrack: Int { weeks.filter { $0.met }.count }

    /// The programme weeks the trend covers, oldest first, clamped to the timeline.
    private var weekRange: [Int] {
        let start = max(app.minWeek, app.week - timeframe.weeks + 1)
        return Array(start...app.week)
    }

    /// Today's weekday as a 0-6 Monday-first index, to match the habit schedule maths.
    /// The tick box acts on this day within `app.week`, so it is genuinely "today" on the
    /// current week and that same weekday when she scrubs back through her history.
    private var todayIndex: Int {
        (Calendar.current.component(.weekday, from: Date()) + 5) % 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider().overlay(Theme.amberSoft.opacity(0.5))
            trendChart
            Divider().overlay(Theme.amberSoft.opacity(0.5))
            todayTable
        }
        .cardBackground()
        .sheet(item: $selection) { sel in
            HabitBarDetailSheet(selection: sel).environmentObject(app)
        }
    }

    // MARK: - Header: the ring of habits on track

    private var header: some View {
        HStack(spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 4) {
                Text("This week").font(.headline).foregroundStyle(Theme.ink)
                Text("\(onTrack) of \(habits.count) habit\(habits.count == 1 ? "" : "s") on track")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var ring: some View {
        let total = max(habits.count, 1)
        let frac = Double(onTrack) / Double(total)
        return ZStack {
            Circle()
                .stroke(Theme.amberSoft.opacity(0.35), lineWidth: 8)
            Circle()
                .trim(from: 0, to: frac)
                .stroke(Theme.amber, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(onTrack)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text("of \(habits.count)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 62, height: 62)
        .animation(.easeInOut(duration: 0.3), value: onTrack)
    }

    // MARK: - Trend chart: an adjustable window of tappable bars

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Habits done each day")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)

            Picker("Time frame", selection: $timeframe) {
                ForEach(Timeframe.allCases) { tf in Text(tf.rawValue).tag(tf) }
            }
            .pickerStyle(.segmented)

            if timeframe == .week {
                // One roomy bar per weekday, filling the width, with its raw count above.
                // Stop at today — a day that hasn't happened yet isn't a bar worth showing.
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0...todayIndex, id: \.self) { day in
                        let a = dayAdherence(app.state.habits, app.state.checkIns, app.week,
                                             app.state.foodEntries, day: day)
                        barColumn(topText: a.scheduled > 0 ? "\(a.done)/\(a.scheduled)" : "",
                                  label: dayLabels[day],
                                  fraction: a.scheduled > 0 ? Double(a.done) / Double(a.scheduled) : 0,
                                  hasValue: a.done > 0) {
                            selection = .day(week: app.week, day: day)
                        }
                    }
                }
            } else {
                // Zoomed out: still one bar per day, just narrower and scrollable, grouped
                // under the programme week they belong to. Opens to the most recent week.
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 14) {
                            ForEach(weekRange, id: \.self) { w in
                                weekDayGroup(w).id(w)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .onAppear { proxy.scrollTo(app.week, anchor: .trailing) }
                    .onChange(of: timeframe) { _, _ in proxy.scrollTo(app.week, anchor: .trailing) }
                }
            }

            Text("Tap a bar to see which habits you did and didn't do.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// One programme week's seven daily bars, with the week number anchored beneath the
    /// group so the labels never crowd at day resolution.
    private func weekDayGroup(_ w: Int) -> some View {
        // The current week stops at today; past weeks are complete, so show all seven.
        let lastDay = w >= app.week ? todayIndex : 6
        return VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0...lastDay, id: \.self) { day in
                    miniDayBar(week: w, day: day)
                }
            }
            Text("W\(w)")
                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    /// A thin daily bar for the zoomed-out window: adherence height, tappable to the same
    /// day breakdown as the wide bars. No count label — the group anchor and the tap do that.
    private func miniDayBar(week: Int, day: Int) -> some View {
        let a = dayAdherence(app.state.habits, app.state.checkIns, week, app.state.foodEntries, day: day)
        let fraction = a.scheduled > 0 ? Double(a.done) / Double(a.scheduled) : 0
        let hasValue = a.done > 0
        let trackHeight: CGFloat = 84
        let fill = trackHeight * CGFloat(min(max(fraction, 0), 1))
        return Button {
            selection = .day(week: week, day: day)
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.amberSoft.opacity(0.25))
                    .frame(width: 9, height: trackHeight)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.amber)
                    .frame(width: 9, height: max(fill, hasValue ? 5 : 0))
            }
            .animation(.easeInOut(duration: 0.3), value: fraction)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One bar in the "this week" chart. `fraction` is 0...1 adherence; `topText` is the raw
    /// count shown above it. The whole column is tappable.
    private func barColumn(topText: String, label: String, fraction: Double,
                           hasValue: Bool, action: @escaping () -> Void) -> some View {
        let trackHeight: CGFloat = 84
        let fill = trackHeight * CGFloat(min(max(fraction, 0), 1))
        return Button(action: action) {
            VStack(spacing: 4) {
                Text(topText.isEmpty ? " " : topText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(hasValue ? Theme.amber : .clear)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Theme.amberSoft.opacity(0.25))
                        .frame(height: trackHeight)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Theme.amber)
                        .frame(height: max(fill, hasValue ? 6 : 0))
                }
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.3), value: fraction)
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Today: one compact row per habit, one tick box each

    /// Every habit in one place with a single tick box for today, so a whole routine fits
    /// on one screen instead of a seven-day grid repeated per habit. The week's running
    /// count still sits on the right, and the trend above carries the history the grids
    /// used to. Rest days and food-evidenced days stay untappable, exactly as the grid did.
    private var todayTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, hw in
                todayRow(hw)
            }
            Text("Tap to tick off today. A moon is a rest day; a fork means it counts from what you logged eating.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func todayRow(_ hw: HabitWeek) -> some View {
        let habit = hw.habit
        let scheduled = habit.isScheduled(on: todayIndex)
        let done = hw.doneDays.contains(todayIndex)
        let fromFood = hw.foodDays.contains(todayIndex)
        let over = habit.direction == .atMost && !hw.met
        return HStack(spacing: 12) {
            todayTick(habit: habit, scheduled: scheduled, done: done, fromFood: fromFood, over: over)
            Text(habit.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text("\(hw.count) of \(habit.target)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(over ? Theme.support : (hw.met ? Theme.steady : Theme.watch))
            Menu {
                Button(role: .destructive) {
                    app.removeHabit(habit.id)
                } label: {
                    Label("Remove habit", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
    }

    /// The single tick box for today. A day she never set the habit for is a rest day
    /// (a faint dashed moon, untappable). A food-evidenced day is answered by the log, so
    /// it shows a fork and stays untappable — it can never read as a missed tick.
    private func todayTick(habit: Habit, scheduled: Bool, done: Bool,
                           fromFood: Bool, over: Bool) -> some View {
        let restDay = !scheduled
        let fill: Color = done ? (over ? Theme.support : Theme.amber) : .clear
        return Button {
            if scheduled && !fromFood { app.toggleCheckIn(habit.id, week: app.week, day: todayIndex) }
        } label: {
            ZStack {
                Circle().fill(fill)
                Circle().stroke(done ? .clear : (restDay ? Theme.amberSoft.opacity(0.4) : Theme.amberSoft),
                                style: StrokeStyle(lineWidth: 1.5, dash: restDay ? [3, 3] : []))
                if done {
                    Image(systemName: fromFood ? "fork.knife" : "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                } else if restDay {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.amberSoft)
                }
            }
            .frame(width: 34, height: 34)
            .opacity(fromFood ? 0.85 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(restDay || fromFood)
    }
}

// MARK: - Bar detail: which habits she did and didn't do

/// The sheet a trend bar opens into. For a day it lists the habits scheduled that day and
/// whether each was done, keeping rest-day habits apart so they never read as misses. For
/// a week it lists every habit she'd set by then and whether it met its aim.
struct HabitBarDetailSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let selection: HabitsDashboardCard.ChartSelection

    private let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        NavigationStack {
            List {
                switch selection {
                case .day(let week, let day): daySections(week: week, day: day)
                case .week(let week): weekSections(week)
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

    private var title: String {
        switch selection {
        case .day(let week, let day): return "\(dayNames[day]) · Week \(week)"
        case .week(let week): return "Week \(week)"
        }
    }

    @ViewBuilder
    private func daySections(week: Int, day: Int) -> some View {
        let active = activeHabits(app.state.habits, week)
        let scheduled = active.filter { $0.isScheduled(on: day) }
        let rest = active.filter { !$0.isScheduled(on: day) }
        let doneCount = scheduled.filter {
            habitWeek($0, app.state.checkIns, week, app.state.foodEntries).doneDays.contains(day)
        }.count

        Section {
            if scheduled.isEmpty {
                Text("No habits scheduled for this day.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(scheduled) { habit in
                    let done = habitWeek(habit, app.state.checkIns, week, app.state.foodEntries)
                        .doneDays.contains(day)
                    statusRow(label: habit.label,
                              icon: done ? "checkmark.circle.fill" : "circle",
                              iconColor: done ? Theme.steady : Theme.amberSoft,
                              trailing: done ? "Done" : "Not done",
                              trailingColor: done ? Theme.steady : Theme.watch)
                }
            }
        } header: {
            Text("\(doneCount) of \(scheduled.count) done")
        }

        if !rest.isEmpty {
            Section {
                ForEach(rest) { habit in
                    statusRow(label: habit.label, icon: "moon.zzz.fill",
                              iconColor: Theme.amberSoft, trailing: "Rest day",
                              trailingColor: Color.secondary)
                }
            } header: {
                Text("Not scheduled today")
            }
        }
    }

    @ViewBuilder
    private func weekSections(_ week: Int) -> some View {
        let active = activeHabits(app.state.habits, week)
        let metCount = active.filter {
            habitWeek($0, app.state.checkIns, week, app.state.foodEntries).met
        }.count

        Section {
            if active.isEmpty {
                Text("No habits set this week.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(active) { habit in
                    let hw = habitWeek(habit, app.state.checkIns, week, app.state.foodEntries)
                    let over = habit.direction == .atMost && !hw.met
                    statusRow(
                        label: habit.label,
                        icon: over ? "exclamationmark.circle.fill" : (hw.met ? "checkmark.circle.fill" : "circle"),
                        iconColor: over ? Theme.support : (hw.met ? Theme.steady : Theme.amberSoft),
                        trailing: "\(hw.count) of \(habit.target)",
                        trailingColor: over ? Theme.support : (hw.met ? Theme.steady : Theme.watch))
                }
            }
        } header: {
            Text("\(metCount) of \(active.count) on track")
        }
    }

    private func statusRow(label: String, icon: String, iconColor: Color,
                           trailing: String, trailingColor: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(iconColor)
            Text(label).font(.subheadline).foregroundStyle(Theme.ink)
            Spacer()
            Text(trailing).font(.caption.weight(.semibold)).foregroundStyle(trailingColor)
        }
    }
}
