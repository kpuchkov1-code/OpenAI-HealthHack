//
//  HabitsView.swift
//  AmberAI
//
//  Accountability tied to her stated reasons. A habit quotes her own words back, never
//  a streak count. The weigh-in is a ceiling ("at most"), so a full week of taps is the
//  failure, not a perfect score — a streak counter could not express that.
//
//  Everything sits in one dashboard card: a ring of what's on track this week, a daily
//  trend she can zoom out over weeks without losing the one-day grain, and a compact
//  table of every habit with a single tick box for today. Ticking today, not filling a
//  seven-day grid per habit, is the daily act — so more habits fit on one screen.
//

import SwiftUI

struct HabitsView: View {
    @EnvironmentObject var app: AppState
    @State private var showFoodLog = false
    @State private var showAddHabit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    WeightProgressSection()

                    logFoodButton

                    let habits = activeHabits(app.state.habits, app.week)
                    if habits.isEmpty {
                        emptyHabits
                    } else {
                        HabitsDashboardCard(habits: habits)
                    }

                    addHabitButton
                }
                .padding()
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddHabit = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add habit")
                }
            }
            .sheet(isPresented: $showFoodLog) {
                FoodLogView().environmentObject(app)
            }
            .sheet(isPresented: $showAddHabit) {
                AddHabitView().environmentObject(app)
            }
        }
    }

    private var emptyHabits: some View {
        VStack(spacing: 8) {
            Image(systemName: "leaf")
                .font(.title)
                .foregroundStyle(Theme.amber)
            Text("No habits yet")
                .font(.headline)
            Text("Set a small, specific habit and the reason behind it.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    /// The way to set a new habit. Kept as a full-width, low-key button so it reads as an
    /// invitation rather than competing with the amber "Log" actions above.
    private var addHabitButton: some View {
        Button {
            showAddHabit = true
        } label: {
            Label("Add a habit", systemImage: "plus.circle")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(Theme.amber)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.amber.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    /// The way into food logging. Lives in Habits because what she logs eating is the
    /// evidence some habit days are counted from.
    private var logFoodButton: some View {
        Button {
            showFoodLog = true
        } label: {
            Label("Log food", systemImage: "plus.viewfinder")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.amber, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

}

// MARK: - Add habit

/// The sheet for setting a new habit. It asks for her own reason ("why") on purpose —
/// that is the line the habit card quotes back to her instead of a streak count.
struct AddHabitView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var why = ""
    @State private var target = 5
    @State private var direction: HabitDirection = .atLeast
    /// The weekdays she means to do this on, 0-6 Monday first. Defaults to every day.
    @State private var scheduledDays: Set<Int> = Set(0..<7)

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    /// The most days a target can name: she can't aim for more days than she's chosen.
    private var maxTarget: Int { max(1, scheduledDays.count) }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !scheduledDays.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    TextField("e.g. Walk after dinner", text: $label)
                }

                Section {
                    daySelector
                } header: {
                    Text("Which days")
                } footer: {
                    Text(scheduledDays.isEmpty
                         ? "Pick at least one day. On days you don't choose, this habit is a rest day — it won't count against your trend."
                         : "On days you don't choose, this habit is a rest day — it won't count against your trend.")
                }

                Section {
                    Picker("Aim", selection: $direction) {
                        Text("At least").tag(HabitDirection.atLeast)
                        Text("At most").tag(HabitDirection.atMost)
                    }
                    .pickerStyle(.segmented)
                    Stepper("\(target) day\(target == 1 ? "" : "s") a week", value: $target, in: 1...maxTarget)
                } header: {
                    Text("How often")
                } footer: {
                    Text(direction == .atMost
                         ? "A ceiling — \(target) or fewer of your \(scheduledDays.count) chosen day\(scheduledDays.count == 1 ? "" : "s") a week counts as holding to it."
                         : "A target — \(target) or more of your \(scheduledDays.count) chosen day\(scheduledDays.count == 1 ? "" : "s") a week counts as met.")
                }

                Section {
                    TextField("Why this matters to you", text: $why, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Your reason")
                } footer: {
                    Text("In your own words. Amber quotes this back to you instead of a streak.")
                }
            }
            .navigationTitle("New habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .tint(Theme.amber)
    }

    /// A row of seven tappable circles for choosing which weekdays the habit is for.
    private var daySelector: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { day in
                let on = scheduledDays.contains(day)
                Button {
                    if on { scheduledDays.remove(day) } else { scheduledDays.insert(day) }
                    // Never let the target outrun the days she's actually chosen.
                    if target > maxTarget { target = maxTarget }
                } label: {
                    Text(dayLabels[day])
                        .font(.caption.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(on ? Theme.amber : Color.clear))
                        .overlay(Circle().stroke(on ? .clear : Theme.amberSoft, lineWidth: 1.5))
                        .foregroundStyle(on ? .white : Theme.ink)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        guard canSave else { return }
        app.addHabit(label: label, why: why, target: target, direction: direction,
                     scheduledDays: scheduledDays.sorted())
        dismiss()
    }
}
