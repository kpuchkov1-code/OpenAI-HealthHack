//
//  Seed.swift
//  AmberAI
//
//  Kirill Puchkov, weeks 1-8. Every habit traces to something he actually said, and
//  the food log deliberately stops at week 2 (see f-015). Ported from lib/seed.ts.
//

import Foundation

enum Patient {
    static let name = "Kirill Puchkov"
    static let firstName = "Kirill"
    static let age = 34
    static let medication = "Mounjaro (tirzepatide)"
    static let prescriber = "Dr Patel"
    static let startedWeek = 1
}

let SEED_FACTS: [MemoryFact] = [
    // Week 1 - starting out
    MemoryFact(id: "f-001", type: .medication, content: "Started Mounjaro at 2.5mg, injecting on Sunday evenings", source: .conversation, weekLearned: 1, salience: 0.95),
    MemoryFact(id: "f-002", type: .personal, content: "Decided to start after seeing a photo of himself at his friend Nadia's birthday and not recognising the person in it", source: .conversation, weekLearned: 1, salience: 0.9),
    MemoryFact(id: "f-003", type: .struggle, content: "Genuinely frightened of needles, sat with the pen on the kitchen table for 40 minutes before the first jab", source: .conversation, weekLearned: 1, salience: 0.85),
    MemoryFact(id: "f-004", type: .personal, content: "Has a rescue whippet called Biscuit who he walks along the canal most mornings", source: .conversation, weekLearned: 1, salience: 0.7),
    MemoryFact(id: "f-005", type: .personal, content: "Works as a project manager at an architecture practice, long days and a lot of desk lunches", source: .conversation, weekLearned: 1, salience: 0.6),
    MemoryFact(id: "f-006", type: .struggle, content: "Has tried and stopped four diets in the last six years and is quietly braced for this to fail the same way", source: .conversation, weekLearned: 1, salience: 0.85),
    MemoryFact(id: "f-007", type: .personal, content: "Keeps the pen in the fridge door behind the oat milk so his flatmate does not ask about it", source: .conversation, weekLearned: 1, salience: 0.45),

    // Week 2 - side effects arrive
    MemoryFact(id: "f-008", type: .symptom, content: "Nausea peaks on day 3 after each dose, usually late afternoon", source: .conversation, weekLearned: 2, salience: 0.9),
    MemoryFact(id: "f-009", type: .symptom, content: "Has gone off chicken completely, the smell of it cooking turns his stomach", source: .conversation, weekLearned: 2, salience: 0.7),
    MemoryFact(id: "f-010", type: .symptom, content: "Sulphurous burps and reflux in the evenings, worse if he eats after 8pm", source: .conversation, weekLearned: 2, salience: 0.65),
    MemoryFact(id: "f-011", type: .personal, content: "Ginger tea and dry oatcakes are the only things that settle his stomach on a bad day", source: .conversation, weekLearned: 2, salience: 0.55),
    MemoryFact(id: "f-012", type: .symptom, content: "Food noise has gone quiet for the first time he can remember, which he finds unsettling as well as good", source: .conversation, weekLearned: 2, salience: 0.9),
    MemoryFact(id: "f-013", type: .personal, content: "Down 1.8 kilograms in the first fortnight, weighs himself on Monday mornings only", source: .conversation, weekLearned: 2, salience: 0.6),

    // Week 3 - the quiet week
    MemoryFact(id: "f-014", type: .struggle, content: "Went quiet for five days in week 3 and later said he had not wanted to admit the scales had not moved", source: .conversation, weekLearned: 3, salience: 0.95),
    MemoryFact(id: "f-015", type: .struggle, content: "Stopped logging meals entirely, said tracking made his feel like he was being marked", source: .conversation, weekLearned: 3, salience: 0.8),
    MemoryFact(id: "f-016", type: .struggle, content: "Low mood, described feeling like he was doing everything right and being punished for it", source: .conversation, weekLearned: 3, salience: 0.9),
    MemoryFact(id: "f-017", type: .personal, content: "Skipped Biscuit's morning walks for most of that week, which he says is his real warning sign", source: .conversation, weekLearned: 3, salience: 0.75),
    MemoryFact(id: "f-018", type: .personal, content: "His sister Mei is getting married in September and Kirill is best man", source: .conversation, weekLearned: 3, salience: 0.85),

    // Week 4 - conversational facts only (consult facts live in Consult.swift)
    MemoryFact(id: "f-019", type: .struggle, content: "Was nervous about the consult, worried Dr Patel would think he had not tried hard enough", source: .conversation, weekLearned: 4, salience: 0.8),
    MemoryFact(id: "f-020", type: .personal, content: "Saving for a trip to Lisbon in October, wants to walk the hills without stopping every hundred metres", source: .conversation, weekLearned: 4, salience: 0.8),
    MemoryFact(id: "f-021", type: .personal, content: "Hates the word \"journey\" and asked not to have it used about him", source: .conversation, weekLearned: 4, salience: 0.5),

    // Week 5 - adjusting to 5mg
    MemoryFact(id: "f-022", type: .symptom, content: "Nausea on 5mg is sharper but shorter, mostly gone by day 4", source: .conversation, weekLearned: 5, salience: 0.75),
    MemoryFact(id: "f-023", type: .medication, content: "Moved his jab to Sunday night before bed and says he now sleeps through the worst of it", source: .conversation, weekLearned: 5, salience: 0.85),
    MemoryFact(id: "f-024", type: .symptom, content: "Very tired by mid afternoon, and worried he is losing muscle rather than fat", source: .conversation, weekLearned: 5, salience: 0.8),
    MemoryFact(id: "f-025", type: .personal, content: "Walked the whole Regent's Canal stretch to Camden and back without needing a sit down, first time in years", source: .conversation, weekLearned: 5, salience: 0.8),
    MemoryFact(id: "f-026", type: .personal, content: "Started two sessions a week at a small gym near work, mostly resistance machines", source: .conversation, weekLearned: 5, salience: 0.65),

    // Week 6 - the plateau
    MemoryFact(id: "f-027", type: .struggle, content: "Weight has not moved for eleven days and he has started weighing himself daily again", source: .conversation, weekLearned: 6, salience: 0.9),
    MemoryFact(id: "f-028", type: .struggle, content: "Said out loud that he is not sure this is worth what it costs him every month", source: .conversation, weekLearned: 6, salience: 0.95),
    MemoryFact(id: "f-029", type: .personal, content: "His suit fitting for Mei's wedding is in three weeks and he is dreading it", source: .conversation, weekLearned: 6, salience: 0.85),
    MemoryFact(id: "f-030", type: .symptom, content: "Appetite has crept back slightly on day 5 and 6 after the dose", source: .conversation, weekLearned: 6, salience: 0.6),

    // Week 5 - read out of his uploaded blood panel. Transcribed, not interpreted.
    MemoryFact(id: "f-031", type: .symptom, content: "Ferritin 18 ug/L on 5 June bloods, flagged low end of range by the lab", source: .document, weekLearned: 5, salience: 0.7, documentId: "d-001"),
    MemoryFact(id: "f-032", type: .clinicalInstruction, content: "Lab comment on 5 June bloods: no action required, repeat ferritin in 3 months", source: .document, weekLearned: 5, salience: 0.75, documentId: "d-001"),
]

let SEED_TIMELINE: [TimelineWeek] = [
    TimelineWeek(week: 1, label: "Starting out", contactDays: [1, 2, 4, 5, 7]),
    TimelineWeek(week: 2, label: "Side effects arrive", contactDays: [8, 9, 10, 12, 13, 14]),
    TimelineWeek(week: 3, label: "The quiet week", contactDays: [15, 21]),
    TimelineWeek(week: 4, label: "Consult and step up", contactDays: [22, 23, 24, 26, 27, 28]),
    TimelineWeek(week: 5, label: "Adjusting to 5mg", contactDays: [29, 30, 32, 33, 35]),
    TimelineWeek(week: 6, label: "Plateau", contactDays: [36, 38, 39, 41, 42]),
    TimelineWeek(week: 7, label: "Gone quiet", contactDays: []),
    TimelineWeek(week: 8, label: "Still quiet", contactDays: []),
]

let SEED_HABITS: [Habit] = [
    Habit(id: "h-walk", label: "Walk Biscuit before work",
          why: "When I stop walking him, something is already wrong. It is my tell.",
          target: 5, direction: .atLeast, createdWeek: 1,
          rationale: "His own early warning sign, in his own words."),
    Habit(id: "h-protein", label: "Protein at breakfast",
          why: "I am not hungry any more, so I just would not eat if I did not plan it.",
          target: 7, direction: .atLeast, createdWeek: 2,
          rationale: "Appetite suppression makes under-eating protein easy. Protein intake is the lever he controls.",
          measuredBy: "food", measure: HabitMeasure(proteinG: 20)),
    Habit(id: "h-resistance", label: "Two resistance sessions",
          why: "I do not want to just get smaller. I want the Lisbon hills.",
          target: 2, direction: .atLeast, createdWeek: 5,
          rationale: "Answers his stated worry about losing muscle rather than fat."),
    Habit(id: "h-weigh", label: "Weigh in once, on Monday",
          why: "Daily weighing turns a flat week into a verdict on me.",
          target: 1, direction: .atMost, createdWeek: 6,
          rationale: "A ceiling, not a target. He set this against himself after the plateau."),
    Habit(id: "h-evening", label: "Kitchen closed by 8pm",
          why: "Eating late gives me reflux and the sulphur burps all night.",
          target: 5, direction: .atLeast, createdWeek: 2,
          rationale: "Ties the evening reflux he reports (worse after 8pm) to the one lever he controls."),
    Habit(id: "h-takeaway", label: "At most two desk-lunch takeaways",
          why: "If I don't plan it, every desk lunch turns into a sad meal deal.",
          target: 2, direction: .atMost, createdWeek: 3,
          rationale: "A weekday ceiling against the desk-lunch pattern he described, set as a limit not a target.",
          scheduledDays: [0, 1, 2, 3, 4]),
    Habit(id: "h-longwalk", label: "A longer walk at the weekend",
          why: "I want the Lisbon hills without stopping every hundred metres.",
          target: 1, direction: .atLeast, createdWeek: 4,
          rationale: "His stated Lisbon goal, kept apart from the daily dog walk so it doesn't get lost in it.",
          scheduledDays: [5, 6]),
    Habit(id: "h-hydrate", label: "Two litres of water",
          why: "Dr Patel said half of what I call fatigue is just not drinking enough.",
          target: 6, direction: .atLeast, createdWeek: 4,
          rationale: "The hydration Dr Patel pushed at the week 4 consult, made into something countable."),
    Habit(id: "h-prep", label: "Batch-cook protein on Sunday",
          why: "If there's no protein ready in the fridge, I just won't eat it.",
          target: 1, direction: .atLeast, createdWeek: 4,
          rationale: "Turns the protein target into a single Sunday action, for the weeks work leaves no time to cook.",
          scheduledDays: [6]),
]

// Check-in history as a per-habit, per-week day map. Days are 0-6, Monday first.
private let CHECKIN_PATTERN: [String: [Int: [Int]]] = [
    "h-walk": [
        1: [0, 1, 3, 4, 5],
        2: [0, 1, 2, 4],
        3: [0],
        4: [0, 1, 3, 4, 6],
        5: [0, 1, 2, 3, 4, 5],
        6: [0, 2, 3, 5],
        7: [1],
        8: [],
    ],
    "h-protein": [
        2: [0, 1, 2, 3, 5],
        3: [0, 2],
        4: [0, 1, 2, 3, 4, 5, 6],
        5: [0, 1, 2, 3, 4, 6],
        6: [0, 1, 3, 4, 5],
        7: [2],
        8: [],
    ],
    "h-resistance": [
        5: [1, 4],
        6: [1, 4],
        7: [],
        8: [],
    ],
    "h-weigh": [
        6: [0, 1, 2, 3, 4, 5, 6],
        7: [0, 1, 2],
        8: [0],
    ],
    "h-evening": [
        2: [0, 1, 2, 4, 5],
        3: [0, 1],
        4: [0, 1, 2, 3, 4],
        5: [0, 1, 2, 3, 5, 6],
        6: [0, 1, 3, 4],
        7: [2],
        8: [],
    ],
    // atMost ceiling: a tick is a day he had a desk-lunch takeaway. Week 6 tips over.
    "h-takeaway": [
        3: [1, 3],
        4: [0, 2],
        5: [1],
        6: [0, 2, 4],
        7: [3],
        8: [],
    ],
    "h-longwalk": [
        4: [5],
        5: [6],
        6: [5, 6],
        7: [],
        8: [],
    ],
    "h-hydrate": [
        4: [0, 1, 2, 3, 4],
        5: [0, 1, 2, 3, 4, 6],
        6: [0, 1, 2, 4, 5],
        7: [1],
        8: [],
    ],
    // Sunday-only prep. Week 4's Sunday hasn't come round yet, so it starts unticked.
    "h-prep": [
        5: [6],
        6: [6],
        7: [],
        8: [6],
    ],
]

let SEED_CHECKINS: [HabitCheckIn] = CHECKIN_PATTERN.flatMap { habitId, weeks in
    weeks.flatMap { week, days in
        days.map { day in HabitCheckIn(habitId: habitId, week: week, day: day, done: true) }
    }
}

/// Compact constructor for the seeded per-serving meals below — the way Kirill mostly
/// logs, by describing a plate (or snapping a photo) so Amber estimates it. Each carries
/// full portion macros, so a day of them adds up into the calendar's nutrition report.
private func meal(_ id: Int, _ week: Int, _ day: Int, _ label: String,
                  _ kcal: Double, _ p: Double, _ c: Double, _ f: Double, _ fib: Double,
                  photo: Bool = false, note: String? = nil) -> FoodEntry {
    FoodEntry(id: String(format: "fe-%03d", id), label: label,
              source: photo ? .photo : .described, week: week, day: day,
              nutrition: FoodNutrition(kcal: kcal, proteinG: p, carbsG: c, fatG: f, fibreG: fib, basis: "per_serving"),
              barcode: nil, provenance: photo ? "Estimated from a photo" : "You described it",
              estimated: true, linkedFactIds: [], note: note)
}

let SEED_FOOD: [FoodEntry] = [
    // The original label-based entries (per 100 g, from a barcode or a search). These
    // stay per-100 g on purpose, so the report shows how label meals are counted but not
    // added into a portion total.
    FoodEntry(id: "fe-001", label: "Organic Porridge Oats, Flahavans", source: .search, week: 1, day: 1,
              nutrition: FoodNutrition(kcal: 371, proteinG: 11, basis: "per_100g"),
              barcode: "4297621003312", provenance: "Open Food Facts · 4297621003312", linkedFactIds: []),
    FoodEntry(id: "fe-002", label: "Nonfat Greek Yogurt, Chobani", source: .barcode, week: 2, day: 1,
              nutrition: FoodNutrition(kcal: 52.9, proteinG: 9.4, basis: "per_100g"),
              barcode: "0894700010137", provenance: "Open Food Facts · 0894700010137", linkedFactIds: []),
    FoodEntry(id: "fe-003", label: "Chicken Korma, Tesco", source: .barcode, week: 2, day: 3,
              nutrition: FoodNutrition(kcal: 160, proteinG: 12.8, carbsG: 3.4, fatG: 10.1, fibreG: 2.3, basis: "per_100g"),
              barcode: "5057753940546", provenance: "Open Food Facts · 5057753940546",
              linkedFactIds: ["f-009", "f-010"], note: "Ate it about nine, after the gym."),
    FoodEntry(id: "fe-004", label: "Ginger tea and two oatcakes", source: .described, week: 2, day: 4,
              provenance: "You told me", linkedFactIds: ["f-008"], note: "The only thing that stayed down."),
] + SEED_MEALS

/// A few weeks of described/photo meals with real portion macros, so tapping most days
/// in the calendar opens a full nutrition report — some days on target, some over, some
/// light. Weeks 3–4 are the most complete (the recent, well-logged stretch).
private let SEED_MEALS: [FoodEntry] = [
    // Week 1 — settling into logging.
    meal(5, 1, 0, "Porridge with berries and peanut butter", 320, 12, 45, 11, 6),
    meal(6, 1, 0, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(7, 1, 0, "Salmon with rice and broccoli", 520, 40, 45, 20, 6, photo: true),
    meal(8, 1, 2, "Two eggs on wholemeal toast", 280, 18, 24, 13, 3),
    meal(9, 1, 2, "Chicken korma with rice", 650, 32, 70, 26, 5),
    meal(10, 1, 2, "Banana", 105, 1, 27, 0, 3),
    meal(11, 1, 4, "Greek yogurt with granola and honey", 240, 18, 28, 6, 2),
    meal(12, 1, 4, "Tofu and veg stir-fry with noodles", 480, 24, 58, 16, 8),
    meal(13, 1, 4, "Apple and a handful of almonds", 210, 6, 22, 13, 5),

    // Week 2 — the nauseous week (see the ginger-tea day above), plus better days.
    meal(14, 2, 0, "Porridge with berries and peanut butter", 320, 12, 45, 11, 6),
    meal(15, 2, 0, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(16, 2, 0, "Spaghetti bolognese", 600, 34, 65, 22, 7),
    meal(17, 2, 5, "Whey protein shake", 160, 30, 6, 2, 1),
    meal(18, 2, 5, "Chicken korma with rice", 650, 32, 70, 26, 5),
    meal(19, 2, 5, "Cheese and crackers", 300, 10, 24, 18, 1),
    meal(20, 2, 5, "Two squares of dark chocolate", 110, 1, 10, 8, 2),

    // Week 3 — the quiet week on the scales, but the food log is full.
    meal(21, 3, 0, "Porridge with berries and peanut butter", 320, 12, 45, 11, 6),
    meal(22, 3, 0, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(23, 3, 0, "Apple and a handful of almonds", 210, 6, 22, 13, 5),
    meal(24, 3, 0, "Salmon with rice and broccoli", 520, 40, 45, 20, 6, photo: true),
    meal(25, 3, 1, "Greek yogurt with granola and honey", 240, 18, 28, 6, 2),
    meal(26, 3, 1, "Lentil soup with a bread roll", 340, 16, 48, 8, 11),
    meal(27, 3, 1, "Banana", 105, 1, 27, 0, 3),
    meal(28, 3, 1, "Spaghetti bolognese", 600, 34, 65, 22, 7),
    meal(29, 3, 2, "Two eggs on wholemeal toast", 280, 18, 24, 13, 3),
    meal(30, 3, 2, "Chicken korma with rice", 650, 32, 70, 26, 5),
    meal(31, 3, 2, "Cheese and crackers", 300, 10, 24, 18, 1),
    meal(32, 3, 2, "Two squares of dark chocolate", 110, 1, 10, 8, 2),
    meal(33, 3, 3, "Whey protein shake", 160, 30, 6, 2, 1),
    meal(34, 3, 3, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(35, 3, 3, "Apple and a handful of almonds", 210, 6, 22, 13, 5),
    meal(36, 3, 3, "Tofu and veg stir-fry with noodles", 480, 24, 58, 16, 8),
    meal(37, 3, 4, "Porridge with berries and peanut butter", 320, 12, 45, 11, 6),
    meal(38, 3, 4, "Salmon with rice and broccoli", 520, 40, 45, 20, 6),
    meal(39, 3, 4, "Cheese and crackers", 300, 10, 24, 18, 1),
    meal(40, 3, 4, "Spaghetti bolognese", 600, 34, 65, 22, 7, note: "Dinner out with Mum — went over, and that's fine."),
    meal(41, 3, 6, "Two eggs on wholemeal toast", 280, 18, 24, 13, 3),
    meal(42, 3, 6, "Chicken korma with rice", 650, 32, 70, 26, 5),
    meal(43, 3, 6, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(44, 3, 6, "Two squares of dark chocolate", 110, 1, 10, 8, 2),

    // Week 4 — the current week by default; the most complete run of days.
    meal(45, 4, 0, "Porridge with berries and peanut butter", 320, 12, 45, 11, 6),
    meal(46, 4, 0, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(47, 4, 0, "Greek yogurt with granola and honey", 240, 18, 28, 6, 2),
    meal(48, 4, 0, "Salmon with rice and broccoli", 520, 40, 45, 20, 6),
    meal(49, 4, 1, "Two eggs on wholemeal toast", 280, 18, 24, 13, 3),
    meal(50, 4, 1, "Lentil soup with a bread roll", 340, 16, 48, 8, 11),
    meal(51, 4, 1, "Apple and a handful of almonds", 210, 6, 22, 13, 5),
    meal(52, 4, 1, "Tofu and veg stir-fry with noodles", 480, 24, 58, 16, 8),
    meal(53, 4, 2, "Whey protein shake", 160, 30, 6, 2, 1),
    meal(54, 4, 2, "Chicken korma with rice", 650, 32, 70, 26, 5),
    meal(55, 4, 2, "Banana", 105, 1, 27, 0, 3),
    meal(56, 4, 2, "Spaghetti bolognese", 600, 34, 65, 22, 7),
    meal(57, 4, 3, "Porridge with berries and peanut butter", 320, 12, 45, 11, 6, photo: true),
    meal(58, 4, 3, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(59, 4, 3, "Cheese and crackers", 300, 10, 24, 18, 1),
    meal(60, 4, 3, "Salmon with rice and broccoli", 520, 40, 45, 20, 6),
    meal(61, 4, 3, "Two squares of dark chocolate", 110, 1, 10, 8, 2),
    meal(62, 4, 4, "Greek yogurt with granola and honey", 240, 18, 28, 6, 2),
    meal(63, 4, 4, "Lentil soup with a bread roll", 340, 16, 48, 8, 11),
    meal(64, 4, 4, "Apple and a handful of almonds", 210, 6, 22, 13, 5),

    // Weeks 5–8 — lighter, so scrubbing forward still opens real days.
    meal(65, 5, 0, "Porridge with berries and peanut butter", 320, 12, 45, 11, 6),
    meal(66, 5, 0, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(67, 5, 0, "Salmon with rice and broccoli", 520, 40, 45, 20, 6),
    meal(68, 5, 3, "Greek yogurt with granola and honey", 240, 18, 28, 6, 2),
    meal(69, 5, 3, "Spaghetti bolognese", 600, 34, 65, 22, 7),
    meal(70, 6, 2, "Two eggs on wholemeal toast", 280, 18, 24, 13, 3),
    meal(71, 6, 2, "Tofu and veg stir-fry with noodles", 480, 24, 58, 16, 8),
    meal(72, 6, 4, "Whey protein shake", 160, 30, 6, 2, 1),
    meal(73, 6, 4, "Chicken korma with rice", 650, 32, 70, 26, 5),
    meal(74, 7, 0, "Porridge with berries and peanut butter", 320, 12, 45, 11, 6),
    meal(75, 7, 0, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(76, 7, 0, "Salmon with rice and broccoli", 520, 40, 45, 20, 6),
    meal(77, 8, 0, "Greek yogurt with granola and honey", 240, 18, 28, 6, 2),
    meal(78, 8, 0, "Lentil soup with a bread roll", 340, 16, 48, 8, 11),
    meal(79, 8, 0, "Spaghetti bolognese", 600, 34, 65, 22, 7),

    // A second, denser pass over the calendar: most days across all eight weeks now open
    // into a full plate of meals, so the nutrition report has real data to add up on
    // almost any day he taps. Weeks 7–8 stay lighter, in keeping with his going quiet.

    // Week 1 — filling the days between the first logged ones.
    meal(80, 1, 1, "Overnight oats with chia and blueberries", 300, 12, 42, 9, 8),
    meal(81, 1, 1, "Turkey meatballs with couscous", 520, 38, 55, 16, 6),
    meal(82, 1, 1, "Cottage cheese with pineapple", 180, 20, 16, 4, 1),
    meal(83, 1, 3, "Scrambled eggs with smoked salmon", 340, 28, 4, 24, 0),
    meal(84, 1, 3, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(85, 1, 3, "Beef chilli with rice", 610, 36, 68, 20, 9),
    meal(86, 1, 5, "Porridge with berries and peanut butter", 320, 12, 45, 11, 6),
    meal(87, 1, 5, "Feta and roasted veg salad", 360, 15, 22, 24, 7),
    meal(88, 1, 5, "Banana", 105, 1, 27, 0, 3),
    meal(89, 1, 6, "Veg omelette", 300, 22, 6, 20, 2, photo: true),
    meal(90, 1, 6, "Prawn stir-fry with rice", 470, 32, 60, 10, 5),
    meal(91, 1, 6, "Apple and a handful of almonds", 210, 6, 22, 13, 5),

    // Week 2 — rounding out the nauseous week; day 4 stays small and plain on purpose.
    meal(92, 2, 1, "Overnight oats with chia and blueberries", 300, 12, 42, 9, 8),
    meal(93, 2, 1, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(94, 2, 1, "Salmon with rice and broccoli", 520, 40, 45, 20, 6),
    meal(95, 2, 2, "Two eggs on wholemeal toast", 280, 18, 24, 13, 3),
    meal(96, 2, 2, "Lentil soup with a bread roll", 340, 16, 48, 8, 11),
    meal(97, 2, 2, "Spaghetti bolognese", 600, 34, 65, 22, 7),
    meal(98, 2, 3, "Greek yogurt with granola and honey", 240, 18, 28, 6, 2),
    meal(99, 2, 3, "Halloumi wrap with salad", 520, 24, 44, 28, 6),
    meal(100, 2, 4, "Miso soup and edamame", 180, 14, 15, 6, 6, note: "Small and plain — a nauseous day."),
    meal(101, 2, 4, "Whey protein shake", 160, 30, 6, 2, 1),
    meal(102, 2, 6, "Porridge with berries and peanut butter", 320, 12, 45, 11, 6),
    meal(103, 2, 6, "Cod with mash and peas", 450, 38, 42, 12, 6),
    meal(104, 2, 6, "Two squares of dark chocolate", 110, 1, 10, 8, 2),

    // Week 3 — the one empty day in an otherwise full week.
    meal(105, 3, 5, "Overnight oats with chia and blueberries", 300, 12, 42, 9, 8),
    meal(106, 3, 5, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(107, 3, 5, "Turkey meatballs with couscous", 520, 38, 55, 16, 6),
    meal(108, 3, 5, "Apple and a handful of almonds", 210, 6, 22, 13, 5),

    // Week 4 — the current week; Saturday (today) logged, Sunday left for the day itself.
    meal(109, 4, 5, "Porridge with berries and peanut butter", 320, 12, 45, 11, 6),
    meal(110, 4, 5, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(111, 4, 5, "Cottage cheese with pineapple", 180, 20, 16, 4, 1),

    // Week 5 — much fuller than before, so scrubbing forward stays worth it.
    meal(112, 5, 1, "Two eggs on wholemeal toast", 280, 18, 24, 13, 3),
    meal(113, 5, 1, "Lentil soup with a bread roll", 340, 16, 48, 8, 11),
    meal(114, 5, 1, "Chicken breast with new potatoes and green beans", 480, 44, 40, 14, 6),
    meal(115, 5, 2, "Greek yogurt with granola and honey", 240, 18, 28, 6, 2),
    meal(116, 5, 2, "Halloumi wrap with salad", 520, 24, 44, 28, 6),
    meal(117, 5, 2, "Beef chilli with rice", 610, 36, 68, 20, 9),
    meal(118, 5, 4, "Overnight oats with chia and blueberries", 300, 12, 42, 9, 8),
    meal(119, 5, 4, "Prawn stir-fry with rice", 470, 32, 60, 10, 5),
    meal(120, 5, 4, "Protein flapjack", 230, 15, 24, 9, 3),
    meal(121, 5, 5, "Porridge with berries and peanut butter", 320, 12, 45, 11, 6),
    meal(122, 5, 5, "Feta and roasted veg salad", 360, 15, 22, 24, 7),
    meal(123, 5, 5, "Banana", 105, 1, 27, 0, 3),
    meal(124, 5, 6, "Veg omelette", 300, 22, 6, 20, 2),
    meal(125, 5, 6, "Spaghetti bolognese", 600, 34, 65, 22, 7),
    meal(126, 5, 6, "Apple and a handful of almonds", 210, 6, 22, 13, 5),

    // Week 6 — the plateau week, logged in full.
    meal(127, 6, 0, "Porridge with berries and peanut butter", 320, 12, 45, 11, 6),
    meal(128, 6, 0, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(129, 6, 0, "Salmon with rice and broccoli", 520, 40, 45, 20, 6),
    meal(130, 6, 1, "Scrambled eggs with smoked salmon", 340, 28, 4, 24, 0),
    meal(131, 6, 1, "Lentil soup with a bread roll", 340, 16, 48, 8, 11),
    meal(132, 6, 1, "Turkey meatballs with couscous", 520, 38, 55, 16, 6),
    meal(133, 6, 3, "Greek yogurt with granola and honey", 240, 18, 28, 6, 2),
    meal(134, 6, 3, "Chicken korma with rice", 650, 32, 70, 26, 5),
    meal(135, 6, 3, "Cottage cheese with pineapple", 180, 20, 16, 4, 1),
    meal(136, 6, 5, "Overnight oats with chia and blueberries", 300, 12, 42, 9, 8),
    meal(137, 6, 5, "Halloumi wrap with salad", 520, 24, 44, 28, 6),
    meal(138, 6, 5, "Two squares of dark chocolate", 110, 1, 10, 8, 2),
    meal(139, 6, 6, "Two eggs on wholemeal toast", 280, 18, 24, 13, 3),
    meal(140, 6, 6, "Cod with mash and peas", 450, 38, 42, 12, 6),
    meal(141, 6, 6, "Apple and a handful of almonds", 210, 6, 22, 13, 5),

    // Week 7 — gone quiet; a couple of days still logged.
    meal(142, 7, 1, "Porridge with berries and peanut butter", 320, 12, 45, 11, 6),
    meal(143, 7, 1, "Chicken and salad wrap", 420, 34, 38, 14, 5),
    meal(144, 7, 2, "Whey protein shake", 160, 30, 6, 2, 1),
    meal(145, 7, 2, "Beef chilli with rice", 610, 36, 68, 20, 9),
    meal(146, 7, 3, "Greek yogurt with granola and honey", 240, 18, 28, 6, 2),
    meal(147, 7, 3, "Tofu and veg stir-fry with noodles", 480, 24, 58, 16, 8),

    // Week 8 — still quiet; a few scattered days.
    meal(148, 8, 1, "Overnight oats with chia and blueberries", 300, 12, 42, 9, 8),
    meal(149, 8, 1, "Lentil soup with a bread roll", 340, 16, 48, 8, 11),
    meal(150, 8, 2, "Two eggs on wholemeal toast", 280, 18, 24, 13, 3),
    meal(151, 8, 2, "Salmon with rice and broccoli", 520, 40, 45, 20, 6),
    meal(152, 8, 3, "Banana", 105, 1, 27, 0, 3),
    meal(153, 8, 3, "Chicken korma with rice", 650, 32, 70, 26, 5),
]

// Monday-morning weigh-ins, the way Kirill says he does it (see f-013). Down 1.8 kg in
// the first fortnight, then the scales stall — the plateau he starts weighing daily
// against in week 6 (f-027). Seeded up to week 6 so scrubbing forward reveals the stall.
let SEED_WEIGHT: [WeightEntry] = [
    // Week 1 — down 1.8 kg across the first fortnight (see f-013).
    WeightEntry(id: "w-001", week: 1, day: 0, kg: 95.4, note: "First Monday on the pen."),
    WeightEntry(id: "w-002", week: 1, day: 3, kg: 95.0, note: nil),
    WeightEntry(id: "w-003", week: 1, day: 6, kg: 94.5, note: nil),
    // Week 2
    WeightEntry(id: "w-004", week: 2, day: 0, kg: 93.6, note: nil),
    WeightEntry(id: "w-005", week: 2, day: 3, kg: 93.7, note: nil),
    WeightEntry(id: "w-006", week: 2, day: 6, kg: 93.4, note: nil),
    // Week 3 — the quiet week, scales barely moving.
    WeightEntry(id: "w-007", week: 3, day: 0, kg: 93.5, note: "Scales barely moved."),
    WeightEntry(id: "w-008", week: 3, day: 4, kg: 93.2, note: nil),
    // Week 4
    WeightEntry(id: "w-009", week: 4, day: 0, kg: 92.7, note: nil),
    WeightEntry(id: "w-010", week: 4, day: 3, kg: 92.4, note: nil),
    WeightEntry(id: "w-011", week: 4, day: 6, kg: 92.1, note: nil),
    // Week 5 — adjusting to 5mg.
    WeightEntry(id: "w-012", week: 5, day: 0, kg: 91.9, note: nil),
    WeightEntry(id: "w-013", week: 5, day: 3, kg: 91.6, note: nil),
    WeightEntry(id: "w-014", week: 5, day: 6, kg: 91.7, note: nil),
    // Week 6 — the plateau, weighing daily again (f-027).
    WeightEntry(id: "w-015", week: 6, day: 0, kg: 91.8, note: nil),
    WeightEntry(id: "w-016", week: 6, day: 2, kg: 91.7, note: "Weighing daily again."),
    WeightEntry(id: "w-017", week: 6, day: 4, kg: 91.9, note: nil),
    WeightEntry(id: "w-018", week: 6, day: 6, kg: 91.6, note: nil),
    // Week 7 — the scales tip over again.
    WeightEntry(id: "w-019", week: 7, day: 0, kg: 91.0, note: nil),
    WeightEntry(id: "w-020", week: 7, day: 3, kg: 90.6, note: nil),
    // Week 8
    WeightEntry(id: "w-021", week: 8, day: 0, kg: 90.2, note: nil),
    WeightEntry(id: "w-022", week: 8, day: 3, kg: 89.7, note: nil),
]

let SEED_DOCUMENTS: [PatientDocument] = [
    PatientDocument(id: "d-001", name: "Bloods_05Jun.pdf", kind: .bloodPanel, uploadedWeek: 5, text: """
THE DOCTORS LABORATORY - Routine Panel
Patient: PUCHKOV, Kirill   DOB: 14/03/1992   Collected: 05/06/2026
Requested by: Dr A. Patel

HbA1c                36 mmol/mol      (ref 20-41)
Ferritin             18 ug/L          (ref 15-150)   LOW END
Haemoglobin          128 g/L          (ref 120-150)
ALT                  22 U/L           (ref 0-33)
eGFR                 >90 mL/min       (ref >90)
TSH                  1.8 mU/L         (ref 0.4-4.0)
Lipase               41 U/L           (ref 13-60)

Comment: No action required on this panel. Repeat ferritin in 3 months.
""", factIds: ["f-031", "f-032"]),
]
