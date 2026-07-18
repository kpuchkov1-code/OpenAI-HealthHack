//
//  Models.swift
//  AmberAI
//
//  The data model for Amber, a companion for people on a long GLP-1 programme.
//  Ported faithfully from the Ember web app (lib/types.ts). Memory is a function
//  of time: every fact carries the week it was learned, so scrubbing backwards
//  makes Amber genuinely forget rather than pretend to.
//

import Foundation

// MARK: - Facts

enum FactType: String, Codable, CaseIterable, Hashable {
    case symptom
    case medication
    case clinicalInstruction = "clinical_instruction"
    case personal
    case struggle
}

/// Where a fact came from. Provenance, not decoration: the Memory screen shows it
/// and the clinician screen leans on it to prove nothing was inferred.
enum FactSource: String, Codable, Hashable {
    case conversation
    case consult
    case document
    case habit
    /// A general line Amber keeps in place of several older, detailed facts. Only ever
    /// synthesised into the model-facing prompt — never stored in `state.facts`.
    case consolidated
}

struct MemoryFact: Identifiable, Codable, Hashable {
    let id: String
    var type: FactType
    var content: String
    var source: FactSource
    var weekLearned: Int
    var salience: Double
    /// Set when source is `.document`. Points at the PatientDocument it was read from.
    var documentId: String?
    /// User-forgotten facts are tombstoned, never deleted, so erasure is auditable.
    var forgotten: Bool?
}

/// A compact, general line that stands in — for the MODEL only — for several older,
/// detailed facts of one category. The originals are never touched, so the Memory
/// screen still shows everything and scrubbing the week back still forgets honestly;
/// this just keeps Amber's working context from piling up as the weeks accumulate.
struct MemoryConsolidation: Identifiable, Codable, Hashable {
    let id: String
    var type: FactType
    /// The generalised summary Amber reads instead of the raw older facts.
    var content: String
    /// The latest `weekLearned` among the facts it summarises.
    var throughWeek: Int
    /// The original facts this stands in for. Kept so the swap is precise and reversible.
    var sourceFactIds: [String]
    /// When Amber compressed them. Gated at prompt time so scrubbing before this week
    /// shows the raw facts again — she can't have summarised what she hadn't yet lived.
    var createdWeek: Int
}

/// A short, durable brief distilled by the LLM from a WHOLE record or consultation —
/// the raw consult transcript, a clinic letter, a lab panel — that the regex reader and
/// the per-fact extractor would each only see in fragments. Model-facing, like a
/// consolidation: it never becomes a `MemoryFact`, so the Memory screen and provenance
/// are unaffected. `createdWeek` gates it, so scrubbing before the record arrived hides
/// it — Amber can't brief herself on something she hadn't yet read.
struct MemoryDigest: Identifiable, Codable, Hashable {
    let id: String            // "digest-consult" or "digest-<documentId>"
    /// Where it came from, shown to nobody but named for the model's benefit.
    var sourceLabel: String
    /// The compact brief Amber reads. Several short lines, transcribed never interpreted.
    var content: String
    /// The week the record entered her knowledge (the consult week, a doc's upload week).
    var createdWeek: Int
    var kind: DocumentKind?
}

struct TimelineWeek: Codable, Hashable {
    let week: Int
    let label: String
    let contactDays: [Int]
}

// MARK: - Turns

enum TurnRole: String, Codable, Hashable {
    case user
    case ember
}

struct Turn: Identifiable, Codable, Hashable {
    /// Not persisted; only for SwiftUI identity.
    var uid = UUID()
    let role: TurnRole
    let text: String
    let week: Int
    let at: Double

    var id: UUID { uid }

    enum CodingKeys: String, CodingKey { case role, text, week, at }

    init(role: TurnRole, text: String, week: Int, at: Double) {
        self.role = role
        self.text = text
        self.week = week
        self.at = at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(TurnRole.self, forKey: .role)
        text = try c.decode(String.self, forKey: .text)
        week = try c.decode(Int.self, forKey: .week)
        at = try c.decode(Double.self, forKey: .at)
        uid = UUID()
    }
}

// MARK: - Habits

enum HabitDirection: String, Codable, Hashable {
    case atLeast = "at_least"
    case atMost = "at_most"
}

struct HabitMeasure: Codable, Hashable {
    var proteinG: Int?
}

/// A habit is not a to-do. `why` is the patient's own words, quoted back to her
/// instead of a streak count.
struct Habit: Identifiable, Codable, Hashable {
    let id: String
    var label: String
    var why: String
    var target: Int
    var direction: HabitDirection
    var createdWeek: Int
    var rationale: String
    var archivedWeek: Int?
    /// "food" when the food log is the evidence rather than a self-reported tick.
    var measuredBy: String?
    var measure: HabitMeasure?
    /// Which weekdays this habit is meant for, 0-6 Monday first. nil means every day —
    /// the back-compat default that seed and food-measured habits use. On a day not in
    /// this set the habit is a rest day: it is never counted, missed, or charted.
    var scheduledDays: [Int]?
}

extension Habit {
    /// The weekdays this habit is active on (0-6, Monday first). A nil `scheduledDays`
    /// means every day, so the common case needs no stored value.
    var activeDays: Set<Int> { scheduledDays.map(Set.init) ?? Set(0..<7) }
    /// True when the habit applies to all seven days — the ordinary case.
    var isEveryDay: Bool { activeDays.count == 7 }
    /// Is the habit meant to be done on `day` (0-6)?
    func isScheduled(on day: Int) -> Bool { activeDays.contains(day) }
}

struct HabitCheckIn: Codable, Hashable {
    let habitId: String
    let week: Int
    /// 0 = Monday. Absolute within the week.
    let day: Int
    var done: Bool
}

// MARK: - Documents

enum DocumentKind: String, Codable, Hashable {
    case bloodPanel = "blood_panel"
    case letter
    case prescription
    case other
}

struct PatientDocument: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var kind: DocumentKind
    var uploadedWeek: Int
    /// The raw text we read. Kept so the Memory screen can show its working.
    var text: String
    var factIds: [String]
}

// MARK: - Food

enum FoodSource: String, Codable, Hashable {
    case described
    case barcode
    case search
    case photo
}

struct FoodNutrition: Codable, Hashable {
    var kcal: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var fibreG: Double?
    /// "per_100g" | "per_serving"
    var basis: String
}

struct FoodEntry: Identifiable, Codable, Hashable {
    let id: String
    var label: String
    var source: FoodSource
    var week: Int
    /// 0 = Monday.
    var day: Int
    var nutrition: FoodNutrition?
    var barcode: String?
    var provenance: String
    /// True only for the photo rung; a guess must not render like a fact.
    var estimated: Bool?
    var linkedFactIds: [String]
    var note: String?
}

// MARK: - Weight

/// A single weigh-in, indexed by programme week + day like everything else so it lines
/// up with food on the calendar and scrubs honestly with `app.week`. One weigh-in per
/// day; a second on the same day replaces the first.
struct WeightEntry: Identifiable, Codable, Hashable {
    let id: String
    var week: Int
    /// 0 = Monday.
    var day: Int
    var kg: Double
    var note: String?
}

// MARK: - Consent & Preferences

/// Load-bearing, not settings-page theatre. Each toggle genuinely removes
/// capability when switched off.
struct Consent: Codable, Hashable {
    var rememberPersonal: Bool
    var proactiveOutreach: Bool
    var shareWithClinician: Bool
}

struct Preferences: Codable, Hashable {
    var voice: String
}

// MARK: - State

struct MemoryState: Codable {
    var facts: [MemoryFact]
    var turns: [Turn]
    var consultIngested: Bool
    var habits: [Habit]
    var checkIns: [HabitCheckIn]
    var documents: [PatientDocument]
    var foodEntries: [FoodEntry]
    var weightEntries: [WeightEntry]
    var consent: Consent
    var preferences: Preferences
    /// Model-facing summaries of older facts. Additive: originals stay in `facts`.
    var consolidations: [MemoryConsolidation]
    /// Model-facing briefs of whole records/consults. Additive, like `consolidations`.
    var digests: [MemoryDigest]

    init(facts: [MemoryFact], turns: [Turn], consultIngested: Bool, habits: [Habit],
         checkIns: [HabitCheckIn], documents: [PatientDocument], foodEntries: [FoodEntry],
         weightEntries: [WeightEntry] = [], consent: Consent, preferences: Preferences,
         consolidations: [MemoryConsolidation] = [], digests: [MemoryDigest] = []) {
        self.facts = facts
        self.turns = turns
        self.consultIngested = consultIngested
        self.habits = habits
        self.checkIns = checkIns
        self.documents = documents
        self.foodEntries = foodEntries
        self.weightEntries = weightEntries
        self.consent = consent
        self.preferences = preferences
        self.consolidations = consolidations
        self.digests = digests
    }

    enum CodingKeys: String, CodingKey {
        case facts, turns, consultIngested, habits, checkIns, documents
        case foodEntries, weightEntries, consent, preferences, consolidations, digests
    }

    /// Decode is tolerant of state files written before `weightEntries` existed, the
    /// same forward-compat contract `AppState.hydrate` relies on.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        facts = try c.decode([MemoryFact].self, forKey: .facts)
        turns = try c.decode([Turn].self, forKey: .turns)
        consultIngested = try c.decode(Bool.self, forKey: .consultIngested)
        habits = try c.decode([Habit].self, forKey: .habits)
        checkIns = try c.decode([HabitCheckIn].self, forKey: .checkIns)
        documents = try c.decode([PatientDocument].self, forKey: .documents)
        foodEntries = try c.decode([FoodEntry].self, forKey: .foodEntries)
        weightEntries = try c.decodeIfPresent([WeightEntry].self, forKey: .weightEntries) ?? []
        consent = try c.decode(Consent.self, forKey: .consent)
        preferences = try c.decode(Preferences.self, forKey: .preferences)
        consolidations = try c.decodeIfPresent([MemoryConsolidation].self, forKey: .consolidations) ?? []
        digests = try c.decodeIfPresent([MemoryDigest].self, forKey: .digests) ?? []
    }
}

// MARK: - Clinician signals

struct SupportSignal: Identifiable, Hashable {
    enum Severity: String { case watch, support }
    var id = UUID()
    var label: String
    var detail: String
    /// The fact ids this signal was derived from. Never inferred from tone.
    var sourceFactIds: [String]
    var severity: Severity
}
