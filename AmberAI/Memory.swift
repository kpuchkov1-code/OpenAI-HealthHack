//
//  Memory.swift
//  AmberAI
//
//  The bit that matters: memory is a function of WHERE YOU ARE IN TIME. Ported from
//  lib/memory.ts. `factsAsOf` (display, tombstones included) and `factsForPrompt`
//  (time + erasure + consent) are separate on purpose.
//

import Foundation

let DEFAULT_CONSENT = Consent(rememberPersonal: true, proactiveOutreach: true, shareWithClinician: true)
let DEFAULT_PREFERENCES = Preferences(voice: DEFAULT_VOICE)

func initialState() -> MemoryState {
    MemoryState(
        facts: SEED_FACTS,
        turns: [],
        consultIngested: false,
        habits: SEED_HABITS,
        checkIns: SEED_CHECKINS,
        documents: SEED_DOCUMENTS,
        foodEntries: SEED_FOOD,
        weightEntries: SEED_WEIGHT,
        consent: DEFAULT_CONSENT,
        preferences: DEFAULT_PREFERENCES)
}

/// Amber only knows what it had learned by `week`. Scrub backwards and it genuinely
/// forgets, because the facts are filtered, not the prompt reworded.
func factsAsOf(_ facts: [MemoryFact], _ week: Int) -> [MemoryFact] {
    facts
        .filter { $0.weekLearned <= week }
        .sorted { a, b in
            if a.salience != b.salience { return a.salience > b.salience }
            return a.weekLearned < b.weekLearned
        }
}

/// How many weeks of memory stay detailed before older facts fold into a general
/// summary. A fact is "old" once it was learned more than this many weeks ago.
let CONSOLIDATION_WINDOW_WEEKS = 4

/// Categories that are safe to generalise. Medication and clinical instructions are
/// deliberately excluded: blurring a dose or a red-flag instruction is a clinical risk,
/// and there are few enough of them that they never drive the pile-up anyway.
let CONSOLIDATABLE_TYPES: Set<FactType> = [.personal, .struggle, .symptom]

/// What Amber is actually allowed to USE: time + erasure + consent. Everything
/// model-facing must go through this, never `factsAsOf`, or the toggles become decorative.
///
/// When `consolidations` are passed, older facts they cover are swapped out for the
/// compact summary the model reads instead — recent weeks stay detailed. The originals
/// are untouched (the Memory screen still shows them); this only shapes the prompt.
func factsForPrompt(_ facts: [MemoryFact], _ week: Int, _ consent: Consent,
                    _ consolidations: [MemoryConsolidation] = []) -> [MemoryFact] {
    let usable = factsAsOf(facts, week).filter { f in
        if f.forgotten == true { return false }
        if !consent.rememberPersonal && f.type == .personal { return false }
        return true
    }
    guard !consolidations.isEmpty else { return usable }

    // Consolidations Amber could have made by this week, respecting the same consent gate.
    let active = consolidations.filter { c in
        c.createdWeek <= week && !(!consent.rememberPersonal && c.type == .personal)
    }
    guard !active.isEmpty else { return usable }

    let oldCutoff = week - CONSOLIDATION_WINDOW_WEEKS
    let visibleIds = Set(usable.map { $0.id })
    let covered = Set(active.flatMap { $0.sourceFactIds })

    // Drop the old, covered originals; keep recent facts and any old fact not yet folded.
    var out = usable.filter { f in
        !(f.weekLearned <= oldCutoff && covered.contains(f.id))
    }

    // Inject each summary as a synthetic, general fact — but only if it still stands in
    // for something visible at this week (so an all-forgotten cluster leaves nothing).
    for c in active where c.sourceFactIds.contains(where: { visibleIds.contains($0) }) {
        out.append(MemoryFact(
            id: c.id, type: c.type, content: c.content, source: .consolidated,
            weekLearned: c.throughWeek, salience: 0.9))
    }

    return out.sorted { a, b in
        if a.salience != b.salience { return a.salience > b.salience }
        return a.weekLearned < b.weekLearned
    }
}

/// Drives the unprompted "you've gone quiet" opener. Derived from the timeline, so
/// scrubbing into weeks 7-8 (no contact) trips it naturally.
func daysSinceLastContact(_ week: Int) -> Int {
    let withContact = SEED_TIMELINE.filter { $0.week <= week && !$0.contactDays.isEmpty }
    guard let last = withContact.last else { return 0 }
    let lastDay = last.contactDays.max() ?? 0
    let nowDay = week * 7
    return max(0, nowDay - lastDay)
}

func nextFactId(_ facts: [MemoryFact]) -> String {
    let nums = facts.compactMap { Int($0.id.replacingOccurrences(of: "f-", with: "")) }
    let maxN = nums.max() ?? 0
    return "f-" + String(format: "%03d", maxN + 1)
}
