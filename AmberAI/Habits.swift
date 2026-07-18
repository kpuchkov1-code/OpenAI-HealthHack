//
//  Habits.swift
//  AmberAI
//
//  Habit maths. Kept separate from the UI because Amber reads it too: the prompt gets
//  the same numbers the Habits screen renders, from the same function. Ported from
//  lib/habits.ts.
//

import Foundation

struct HabitWeek {
    let habit: Habit
    let week: Int
    /// 0-6, Monday first.
    let doneDays: [Int]
    let count: Int
    /// Did he hold to it this week, respecting direction?
    let met: Bool
    /// The subset of doneDays the food log evidenced on its own.
    let foodDays: [Int]
    /// Convenience for the UI. foodDays.count > 0.
    let measured: Bool
}

/// Habits he had actually set by `week`. Time filtering, same as facts.
func activeHabits(_ habits: [Habit], _ week: Int) -> [Habit] {
    habits.filter { h in
        h.createdWeek <= week && (h.archivedWeek == nil || h.archivedWeek! > week)
    }
}

func habitWeek(_ habit: Habit, _ checkIns: [HabitCheckIn], _ week: Int, _ foodEntries: [FoodEntry]) -> HabitWeek {
    let ticked = checkIns
        .filter { $0.habitId == habit.id && $0.week == week && $0.done }
        .map { $0.day }

    // The food log ADDS evidence; it does not replace his word. A day counts if he
    // said it counted, or if what he logged clears the floor on its own.
    let fromFood: [Int] = habit.measuredBy == "food"
        ? daysMeetingProtein(foodEntries, week, Double(habit.measure?.proteinG ?? 0))
        : []

    let doneDays = Array(Set(ticked + fromFood)).sorted()
    let count = doneDays.count
    let met = habit.direction == .atMost ? count <= habit.target : count >= habit.target

    return HabitWeek(habit: habit, week: week, doneDays: doneDays, count: count, met: met,
                     foodDays: fromFood, measured: !fromFood.isEmpty)
}

/// How a single week landed, for the trend strip. Distinct from `met` because the strip
/// needs to tell "under target" apart from "over his ceiling" — opposite meanings that a
/// bool cannot carry. `.before` is a week he had not set the habit yet.
enum HabitOutcome {
    case met      // held to it, respecting direction
    case over     // an atMost habit he went past — a limit, not a score
    case under    // an atLeast habit he fell short on
    case before   // habit not set yet this week
}

func weekOutcome(_ habit: Habit, _ checkIns: [HabitCheckIn], _ week: Int, _ foodEntries: [FoodEntry]) -> HabitOutcome {
    guard week >= habit.createdWeek else { return .before }
    let hw = habitWeek(habit, checkIns, week, foodEntries)
    if habit.direction == .atMost { return hw.met ? .met : .over }
    return hw.met ? .met : .under
}

// MARK: - Trend chart data

/// One weekday's adherence within a week: how many of the habits *scheduled* for that day
/// he actually did. Habits he didn't set for this day are left out of both figures — a
/// rest day never reads as a miss.
struct DayAdherence {
    let day: Int          // 0-6, Monday first
    let done: Int
    let scheduled: Int
}

func dayAdherence(_ habits: [Habit], _ checkIns: [HabitCheckIn], _ week: Int,
                  _ foodEntries: [FoodEntry], day: Int) -> DayAdherence {
    let scheduled = activeHabits(habits, week).filter { $0.isScheduled(on: day) }
    let done = scheduled.filter { habitWeek($0, checkIns, week, foodEntries).doneDays.contains(day) }
    return DayAdherence(day: day, done: done.count, scheduled: scheduled.count)
}

/// How a whole week landed across every habit he had set by then: how many met their aim
/// out of how many were active. The denominator excludes habits not yet set, so earlier
/// weeks in the trend read honestly rather than as a wall of misses.
struct WeekAdherence {
    let week: Int
    let met: Int
    let total: Int
}

func weekAdherence(_ habits: [Habit], _ checkIns: [HabitCheckIn], _ week: Int,
                   _ foodEntries: [FoodEntry]) -> WeekAdherence {
    let active = activeHabits(habits, week)
    let met = active.filter { habitWeek($0, checkIns, week, foodEntries).met }
    return WeekAdherence(week: week, met: met.count, total: active.count)
}

/// A compact human label for a habit's scheduled weekdays, e.g. "Mon · Wed · Fri".
func scheduleLabel(_ habit: Habit) -> String {
    if habit.isEveryDay { return "Every day" }
    let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    return habit.activeDays.sorted().map { names[$0] }.joined(separator: " · ")
}

/// Consecutive weeks met, counting back from `week` inclusive. Stops at the week the
/// habit was created.
func streak(_ habit: Habit, _ checkIns: [HabitCheckIn], _ week: Int, _ foodEntries: [FoodEntry]) -> Int {
    var n = 0
    var w = week
    while w >= habit.createdWeek {
        if !habitWeek(habit, checkIns, w, foodEntries).met { break }
        n += 1
        w -= 1
    }
    return n
}

/// What Amber is told about his habits. Observations, not scores.
func habitsForPrompt(_ habits: [Habit], _ checkIns: [HabitCheckIn], _ week: Int, _ foodEntries: [FoodEntry]) -> String {
    let active = activeHabits(habits, week)
    if active.isEmpty { return "" }

    let lines = active.map { h -> String in
        let now = habitWeek(h, checkIns, week, foodEntries)
        let prev = week > h.createdWeek ? habitWeek(h, checkIns, week - 1, foodEntries) : nil
        let aim = h.direction == .atMost ? "at most \(h.target) a week" : "\(h.target) a week"
        var trend = ""
        if let prev {
            if now.count < prev.count { trend = ", down from \(prev.count) last week" }
            else if now.count > prev.count { trend = ", up from \(prev.count) last week" }
        }
        let over = (h.direction == .atMost && !now.met) ? " (over his own limit)" : ""
        return "  - \(h.label): \(now.count) of \(aim) this week\(trend)\(over). He set it because: \"\(h.why)\""
    }

    return """
    Habits he has set for himself, and how this week has actually gone:
    \(lines.joined(separator: "\n"))

    Use these the way a friend would. Name the specific thing, once, and only if it is \
    worth naming. Never quote a percentage or a streak count at his. If he has slipped, \
    do not open with it and do not scold his; he already knows.
    """
}
