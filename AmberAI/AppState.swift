//
//  AppState.swift
//  AmberAI
//
//  The single source of truth. Replaces the web app's API routes + WeekProvider +
//  file store. Holds MemoryState and the current programme week, persists to disk,
//  and owns every mutation. `week` lives here so all screens agree on where in time
//  we are, which is what makes forgetting consistent across tabs.
//

import Foundation
import SwiftUI
import Combine

struct ChatOutcome {
    let reply: String
    let safety: SafetyHit?
}

@MainActor
final class AppState: ObservableObject {
    @Published var state: MemoryState
    /// Where we are in her programme. Scrub it and memory shrinks or grows honestly.
    @Published var week: Int = 4
    /// Ids added by the most recent extraction, so the Memory drawer can highlight them.
    @Published private(set) var lastAddedFactIds: Set<String> = []
    @Published var lastError: String?

    /// The latest snapshot from each connected wearable, injected into Amber's context.
    /// In-memory only — the devices/services are the source of truth, re-read on launch and
    /// when Settings opens — so there's nothing to persist here.
    @Published var wearableSummaries: [WearableSummary] = []

    /// Guards against overlapping consolidation passes while one is in flight.
    private var isConsolidating = false
    /// Guards against overlapping record-digest passes while one is in flight.
    private var isDigesting = false

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("amber-state.json")

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(MemoryState.self, from: data) {
            state = AppState.hydrate(loaded)
        } else {
            state = initialState()
        }
    }

    // MARK: - Persistence

    /// Fill in defaults so a state file written before a field existed still loads, and
    /// so an undefined consent flag can never silently switch a feature off.
    private static func hydrate(_ s: MemoryState) -> MemoryState {
        var out = s
        if !isVoice(out.preferences.voice) { out.preferences.voice = DEFAULT_VOICE }
        // Weight seeding was added after the first state files were written, so a state
        // saved before then has no weigh-ins. Backfill Sarah's seed history when the list
        // is empty, so the trend and calendar show mock data without needing a full reset.
        if out.weightEntries.isEmpty { out.weightEntries = SEED_WEIGHT }

        // Seed records (the eMed pack) added after the first state files were written won't
        // be in an existing install's saved state. Reconcile each seed document against the
        // saved state: make sure the facts it reads from exist, and force its factIds back to
        // the seed's own ids. The force-set is what heals an install corrupted by an earlier
        // build that seeded these facts in the "f-NNN" space, where a conversation fact could
        // hold the same id and get shown under the document. Seed fact ids now live in the
        // "f-em*" namespace, which nextFactId never mints, so the collision cannot recur.
        // Only seed documents are touched; a record she uploaded herself is never altered.
        for seedDoc in SEED_DOCUMENTS {
            let haveFacts = Set(out.facts.map { $0.id })
            for factId in seedDoc.factIds where !haveFacts.contains(factId) {
                if let seedFact = SEED_FACTS.first(where: { $0.id == factId }) {
                    out.facts.append(seedFact)
                }
            }
            if let i = out.documents.firstIndex(where: { $0.id == seedDoc.id }) {
                out.documents[i].factIds = seedDoc.factIds
            } else {
                out.documents.append(seedDoc)
            }
        }

        // The two eMed seed documents (the treatment plan and the GP letter) were retired.
        // The additive reconcile above never removes a doc, so an install that saved state
        // while they were still seeded would keep them. Prune those docs and the facts they
        // read by their known ids; records she uploaded herself are never touched.
        let retiredSeedDocIds: Set<String> = ["d-002", "d-004"]
        let retiredSeedFactIds: Set<String> = ["f-em1", "f-em2", "f-em3"]
        out.documents.removeAll { retiredSeedDocIds.contains($0.id) }
        out.facts.removeAll { retiredSeedFactIds.contains($0.id) }

        // Seed habits, their check-in history, and the food calendar are all expanded from
        // build to build. A state file written before those additions is missing them, so
        // reconcile each by id: append anything the saved state doesn't already have, and
        // leave everything she logged herself untouched. Additive, exactly like the seed
        // documents above — nothing she added is ever overwritten or removed.
        let haveHabits = Set(out.habits.map { $0.id })
        for habit in SEED_HABITS where !haveHabits.contains(habit.id) {
            out.habits.append(habit)
        }
        let haveCheckIns = Set(out.checkIns)
        for checkIn in SEED_CHECKINS where !haveCheckIns.contains(checkIn) {
            out.checkIns.append(checkIn)
        }
        let haveFood = Set(out.foodEntries.map { $0.id })
        for entry in SEED_FOOD where !haveFood.contains(entry.id) {
            out.foodEntries.append(entry)
        }

        // The seed itself is edited between builds — a renamed patient, reworded habits, a
        // corrected letter. A saved state still holds the OLD wording under the same ids, so
        // refresh every seed-owned record's text in place: content for seed facts, the label
        // and reason for seed habits, the body of seed documents. Only fields the seed
        // authors are touched — tombstones, check-ins, and meals logged in the app are left
        // exactly as they were.
        let seedFactContent = Dictionary(uniqueKeysWithValues: (SEED_FACTS + CONSULT_FACTS).map { ($0.id, $0.content) })
        for i in out.facts.indices {
            if let content = seedFactContent[out.facts[i].id] {
                out.facts[i].content = content
            }
        }
        let seedHabitsById = Dictionary(uniqueKeysWithValues: SEED_HABITS.map { ($0.id, $0) })
        for i in out.habits.indices {
            if let h = seedHabitsById[out.habits[i].id] {
                out.habits[i].label = h.label
                out.habits[i].why = h.why
                out.habits[i].rationale = h.rationale
            }
        }
        let seedDocText = Dictionary(uniqueKeysWithValues: SEED_DOCUMENTS.map { ($0.id, $0.text) })
        for i in out.documents.indices {
            if let text = seedDocText[out.documents[i].id] {
                out.documents[i].text = text
            }
        }

        return out
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: fileURL)
        }
    }

    // MARK: - Derived

    /// Display facts for the current week, tombstones included (the Memory screen wants
    /// to show a forgotten fact struck through, not vanished).
    var displayedFacts: [MemoryFact] { factsAsOf(state.facts, week) }

    /// What Amber may actually use: time + erasure + consent + consolidation.
    var usableFacts: [MemoryFact] { factsForPrompt(state.facts, week, state.consent, state.consolidations) }

    /// Consolidations in force at the current week, for the Memory screen's banner.
    var activeConsolidations: [MemoryConsolidation] {
        state.consolidations.filter { c in
            c.createdWeek <= week && !(!state.consent.rememberPersonal && c.type == .personal)
        }
    }

    /// Facts she has told Amber (tombstones removed) at this week.
    var knownCount: Int { displayedFacts.filter { $0.forgotten != true }.count }
    var usableCount: Int { usableFacts.count }
    /// The live cost of her consent choices: facts withheld from the model.
    var consentCost: Int { max(0, knownCount - usableCount) }

    var signals: [SupportSignal] { deriveSignals(state, week) }
    var verdict: SupportVerdict { supportVerdict(signals) }
    var quietDays: Int { daysSinceLastContact(week) }

    var timeline: [TimelineWeek] { SEED_TIMELINE }
    var minWeek: Int { SEED_TIMELINE.map { $0.week }.min() ?? 1 }
    var maxWeek: Int { SEED_TIMELINE.map { $0.week }.max() ?? 8 }
    var weekLabel: String { SEED_TIMELINE.first { $0.week == week }?.label ?? "Week \(week)" }

    // MARK: - Memory mutations

    func forget(_ factId: String) {
        guard let i = state.facts.firstIndex(where: { $0.id == factId }) else { return }
        state.facts[i].forgotten = true
        persist()
    }

    func unforget(_ factId: String) {
        guard let i = state.facts.firstIndex(where: { $0.id == factId }) else { return }
        state.facts[i].forgotten = false
        persist()
    }

    /// The forgotten facts visible as of the current week — the "Recently Deleted" pile.
    /// They're tombstoned, so `factsForPrompt` already keeps them out of Amber's context;
    /// this just surfaces them apart from the live list so the Memory screen can offer
    /// restore-or-erase without cluttering what Amber actually knows.
    var recentlyDeletedFacts: [MemoryFact] {
        displayedFacts.filter { $0.forgotten == true }
    }

    /// Drop a forgotten fact from the store for good. Guarded on `forgotten` so a fact
    /// must be tombstoned first — nothing can be erased straight out of the live list.
    func permanentlyDelete(_ factId: String) {
        state.facts.removeAll { $0.id == factId && $0.forgotten == true }
        persist()
    }

    /// Restore every recently-deleted fact at once.
    func restoreAllDeleted() {
        for i in state.facts.indices where state.facts[i].forgotten == true {
            state.facts[i].forgotten = false
        }
        persist()
    }

    // MARK: - Consult

    var consultIngested: Bool { state.consultIngested }

    /// Lands the 7 clinical facts from the Dr Patel consult, tagged `consult`.
    func ingestConsult() {
        guard !state.consultIngested else { return }
        let existing = Set(state.facts.map { $0.id })
        let toAdd = CONSULT_FACTS.filter { !existing.contains($0.id) }
        state.facts.append(contentsOf: toAdd)
        state.consultIngested = true
        lastAddedFactIds = Set(toAdd.map { $0.id })
        persist()
    }

    // MARK: - Consent

    func setRememberPersonal(_ v: Bool) { state.consent.rememberPersonal = v; persist() }
    func setProactiveOutreach(_ v: Bool) { state.consent.proactiveOutreach = v; persist() }
    func setShareWithClinician(_ v: Bool) { state.consent.shareWithClinician = v; persist() }

    // MARK: - Habits

    func isChecked(_ habitId: String, week: Int, day: Int) -> Bool {
        state.checkIns.contains { $0.habitId == habitId && $0.week == week && $0.day == day && $0.done }
    }

    func toggleCheckIn(_ habitId: String, week: Int, day: Int) {
        if let i = state.checkIns.firstIndex(where: { $0.habitId == habitId && $0.week == week && $0.day == day }) {
            state.checkIns[i].done.toggle()
            if !state.checkIns[i].done { state.checkIns.remove(at: i) }
        } else {
            state.checkIns.append(HabitCheckIn(habitId: habitId, week: week, day: day, done: true))
        }
        persist()
    }

    /// Add a habit she set for herself, live from the current week. `why` is her own
    /// words — the thing the card quotes back instead of a streak.
    @discardableResult
    func addHabit(label: String, why: String, target: Int, direction: HabitDirection,
                  scheduledDays: [Int]? = nil) -> Habit {
        let id = "h-" + UUID().uuidString.prefix(6).lowercased()
        // Normalise the schedule: unique, in-range, sorted. "All seven" is stored as nil
        // so an everyday habit needs no special-casing and stays back-compatible.
        let picked = scheduledDays.map { Set($0).filter { (0..<7).contains($0) } }
        let normalized: [Int]? = (picked == nil || picked!.count == 7 || picked!.isEmpty)
            ? nil : picked!.sorted()
        // A target can never exceed the number of days the habit is even meant for.
        let dayCount = normalized?.count ?? 7
        let habit = Habit(
            id: String(id),
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            why: why.trimmingCharacters(in: .whitespacesAndNewlines),
            target: max(1, min(dayCount, target)),
            direction: direction,
            createdWeek: week,
            rationale: "Set by him in the app.",
            scheduledDays: normalized)
        state.habits.append(habit)
        persist()
        return habit
    }

    /// Remove a habit and the check-ins tied to it. A clean delete, since a habit she
    /// added and dropped shouldn't linger in her history.
    func removeHabit(_ habitId: String) {
        state.habits.removeAll { $0.id == habitId }
        state.checkIns.removeAll { $0.habitId == habitId }
        persist()
    }

    // MARK: - Documents

    /// Parse a pasted record deterministically and land any facts it prints.
    @discardableResult
    func addDocument(name: String, text: String) -> [MemoryFact] {
        let kind = classifyKind(name: name, text: text)
        let docId = "d-" + String(format: "%03d", state.documents.count + 1)
        let parsed = parseDocument(text)

        var added: [MemoryFact] = []
        for p in parsed {
            let dup = (state.facts + added).contains { $0.content.lowercased() == p.content.lowercased() }
            if dup { continue }
            added.append(MemoryFact(
                id: nextFactId(state.facts + added),
                type: p.type, content: p.content, source: .document,
                weekLearned: week, salience: p.salience, documentId: docId))
        }

        let doc = PatientDocument(id: docId, name: name.isEmpty ? "Pasted record" : name,
                                  kind: kind, uploadedWeek: week, text: text,
                                  factIds: added.map { $0.id })
        state.documents.append(doc)
        state.facts.append(contentsOf: added)
        lastAddedFactIds = Set(added.map { $0.id })
        persist()
        return added
    }

    func factsFor(document: PatientDocument) -> [MemoryFact] {
        state.facts.filter { document.factIds.contains($0.id) }
    }

    // MARK: - Live consult (Amber sits in on an appointment)

    /// Save a transcript Amber captured live while listening in on an appointment. A
    /// spoken consult has none of the structured lines the regex reader looks for, so its
    /// durable facts come from the same LLM extractor the chat path uses — tagged
    /// `.consult` for provenance, exactly like the curated Dr Patel facts. The whole
    /// transcript is also kept as a record and briefed into a digest, so it reaches both
    /// the model's working memory and the report for her doctor. Extraction is
    /// best-effort: the record and its digest stand even if the model call fails, so a
    /// captured appointment is never lost.
    @discardableResult
    func addLiveConsult(meetingLink: String, transcript rawTranscript: String) async -> [MemoryFact] {
        let transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return [] }

        let link = meetingLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let docId = "d-" + String(format: "%03d", state.documents.count + 1)

        // Durable clinical facts, from the same extractor the chat uses, tagged .consult
        // and pointed at the record so the document sheet can show its working.
        var added: [MemoryFact] = []
        do {
            let raw = try await Runware.text(system: EXTRACTION_PROMPT,
                                             messages: [RunwareMessage(role: "user", content: transcript)],
                                             temperature: 0.2, maxTokens: 800)
            if let parsed = parseJsonLoose(raw), let facts = parsed["facts"] as? [[String: Any]] {
                let valid = Set(FactType.allCases.map { $0.rawValue })
                for f in facts {
                    let content = ((f["content"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if content.isEmpty { continue }
                    let typeRaw = (f["type"] as? String) ?? ""
                    let type = valid.contains(typeRaw) ? FactType(rawValue: typeRaw)! : .personal
                    let dup = (state.facts + added).contains { $0.content.lowercased() == content.lowercased() }
                    if dup { continue }
                    let sal = (f["salience"] as? Double) ?? (f["salience"] as? NSNumber)?.doubleValue ?? 0.7
                    added.append(MemoryFact(
                        id: nextFactId(state.facts + added),
                        type: type, content: content, source: .consult,
                        weekLearned: week, salience: min(1, max(0, sal)), documentId: docId))
                }
            }
        } catch {
            // Best-effort; a failure must not lose the transcript. Its record still lands.
        }

        // The stored record keeps the meeting link as a header, then the raw transcript,
        // so the Memory screen shows exactly what Amber heard, unedited.
        let body = link.isEmpty ? transcript : "Meeting link: \(link)\n\n\(transcript)"
        let doc = PatientDocument(id: docId, name: "Appointment Amber sat in on",
                                  kind: .letter, uploadedWeek: week, text: body,
                                  factIds: added.map { $0.id })
        state.documents.append(doc)
        state.facts.append(contentsOf: added)
        lastAddedFactIds = Set(added.map { $0.id })
        persist()

        // Brief the whole conversation now, so its durable summary reaches the model and
        // the doctor report immediately rather than waiting for the next chat turn.
        await digestRecordsIfNeeded()
        return added
    }

    // MARK: - Food

    /// Land a logged food at the current week and the chosen day. Additive: it only
    /// appends to `foodEntries`, which the Habits circles and the prompt already read.
    @discardableResult
    func addFood(_ draft: FoodDraft, day: Int) -> FoodEntry {
        let entry = FoodEntry(
            id: nextFoodId(state.foodEntries),
            label: draft.label,
            source: draft.source,
            week: week,
            day: day,
            nutrition: draft.nutrition,
            barcode: draft.barcode,
            provenance: draft.provenance,
            estimated: draft.estimated,
            linkedFactIds: [],
            note: draft.note)
        state.foodEntries.append(entry)
        persist()
        return entry
    }

    // MARK: - Weight

    /// The most recent weigh-in she can see at the current week.
    var currentWeight: WeightEntry? { latestWeight(state.weightEntries, week) }

    /// Land a weigh-in at the current week and chosen day. One weigh-in per day: a
    /// second entry on the same day replaces the first, so the trend never double-counts.
    @discardableResult
    func addWeight(kg: Double, day: Int, note: String?) -> WeightEntry {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = WeightEntry(
            id: nextWeightId(state.weightEntries),
            week: week,
            day: day,
            kg: kg,
            note: (trimmed?.isEmpty == false) ? trimmed : nil)
        state.weightEntries.removeAll { $0.week == week && $0.day == day }
        state.weightEntries.append(entry)
        persist()
        return entry
    }

    // MARK: - Reset

    func reset() {
        state = initialState()
        lastAddedFactIds = []
        lastError = nil
        persist()
    }

    // MARK: - Conversation

    /// One reply. Runs the static safety check first (no model sees a flagged message),
    /// then builds the same consent/time-filtered instructions and asks Runware.
    func reply(to message: String) async -> ChatOutcome {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hit = checkSafety(trimmed) {
            return ChatOutcome(reply: safetyReply(hit), safety: hit)
        }
        await consolidateMemoryIfNeeded()
        await digestRecordsIfNeeded()
        let instructions = buildInstructions(state, week, wearables: wearablesPromptBlock(wearableSummaries))
        let history = state.turns.suffix(8).map {
            RunwareMessage(role: $0.role == .user ? "user" : "assistant", content: $0.text)
        }
        do {
            let reply = try await Runware.text(
                system: instructions,
                messages: history + [RunwareMessage(role: "user", content: trimmed)],
                temperature: 0.8, maxTokens: 200)
            return ChatOutcome(reply: reply.trimmingCharacters(in: .whitespacesAndNewlines), safety: nil)
        } catch {
            lastError = (error as? RunwareError)?.message ?? error.localizedDescription
            return ChatOutcome(reply: "", safety: nil)
        }
    }

    /// The write half of memory: record the exchange and extract durable facts from it.
    /// Runs after each exchange so a judge can watch their fact land in the drawer.
    ///
    /// `extract` is false when Amber has already written this turn's fact herself through
    /// the `remember` tool: the exchange is still recorded, but the passive extractor is
    /// skipped so the same fact doesn't land twice in slightly different words.
    func commitExchange(user: String, amber: String, at: Double, extract: Bool = true) async {
        let newTurns = [
            Turn(role: .user, text: user, week: week, at: at),
            Turn(role: .ember, text: amber, week: week, at: at + 1),
        ]
        state.turns.append(contentsOf: newTurns)

        guard extract else { persist(); return }

        let transcript = newTurns
            .map { "\($0.role == .user ? "Patient" : "Amber"): \($0.text)" }
            .joined(separator: "\n")

        var added: [MemoryFact] = []
        do {
            let raw = try await Runware.text(system: EXTRACTION_PROMPT,
                                             messages: [RunwareMessage(role: "user", content: transcript)],
                                             temperature: 0.2, maxTokens: 800)
            if let parsed = parseJsonLoose(raw), let facts = parsed["facts"] as? [[String: Any]] {
                let valid = Set(FactType.allCases.map { $0.rawValue })
                for f in facts {
                    let content = ((f["content"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if content.isEmpty { continue }
                    let typeRaw = (f["type"] as? String) ?? ""
                    let type = valid.contains(typeRaw) ? FactType(rawValue: typeRaw)! : .personal
                    let dup = (state.facts + added).contains { $0.content.lowercased() == content.lowercased() }
                    if dup { continue }
                    let sal = (f["salience"] as? Double) ?? (f["salience"] as? NSNumber)?.doubleValue ?? 0.6
                    added.append(MemoryFact(
                        id: nextFactId(state.facts + added),
                        type: type, content: content, source: .conversation,
                        weekLearned: week, salience: min(1, max(0, sal))))
                }
            }
        } catch {
            // Extraction is best-effort; a failure must not lose the exchange.
        }

        state.facts.append(contentsOf: added)
        lastAddedFactIds = Set(added.map { $0.id })
        persist()
    }

    // MARK: - Agentic memory

    /// Amber's own hand on the pen. Called when she decides mid-conversation, through the
    /// realtime `remember` tool, that something is worth keeping — rather than waiting for
    /// the passive post-turn extractor. Lands one durable fact, deduped, at the current
    /// week. Returns nil (nothing saved) on a blank line, a duplicate, or a personal fact
    /// she has told us not to keep — so the consent toggle stays load-bearing here too.
    @discardableResult
    func rememberFact(content rawContent: String, typeRaw: String, salience: Double) -> MemoryFact? {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        let valid = Set(FactType.allCases.map { $0.rawValue })
        let type = valid.contains(typeRaw) ? FactType(rawValue: typeRaw)! : .personal
        if type == .personal && !state.consent.rememberPersonal { return nil }

        let dup = state.facts.contains { $0.content.lowercased() == content.lowercased() }
        if dup { return nil }

        let fact = MemoryFact(
            id: nextFactId(state.facts), type: type, content: content,
            source: .conversation, weekLearned: week, salience: min(1, max(0, salience)))
        state.facts.append(fact)
        lastAddedFactIds = [fact.id]
        persist()
        return fact
    }

    // MARK: - Record digests

    /// The whole-record half of the record path. The regex reader and the per-turn
    /// extractor see records in fragments; this reads each record end to end and keeps a
    /// short durable brief the model carries instead. Additive and lazy, exactly like
    /// consolidation: run just before instructions are built, skip anything already
    /// briefed, and gate each brief to the week its record arrived. On any failure the
    /// existing facts still cover the record, so nothing is lost.
    func digestRecordsIfNeeded() async {
        guard !isDigesting else { return }
        isDigesting = true
        defer { isDigesting = false }

        var updated = state.digests
        var changed = false

        // The Dr Patel consultation, read whole rather than as the seven curated facts.
        if state.consultIngested && !updated.contains(where: { $0.id == "digest-consult" }) {
            let transcript = CONSULT_TRANSCRIPT.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
            if let brief = await makeDigest(source: "the week \(CONSULT_WEEK) consultation with Dr Patel", text: transcript) {
                updated.append(MemoryDigest(
                    id: "digest-consult", sourceLabel: "his week \(CONSULT_WEEK) consult with Dr Patel",
                    content: brief, createdWeek: CONSULT_WEEK, kind: nil))
                changed = true
            }
        }

        // Every pasted record, digested once, gated to the week it was uploaded.
        for doc in state.documents where !updated.contains(where: { $0.id == "digest-\(doc.id)" }) {
            if let brief = await makeDigest(source: "a patient record titled \"\(doc.name)\"", text: doc.text) {
                updated.append(MemoryDigest(
                    id: "digest-\(doc.id)", sourceLabel: doc.name,
                    content: brief, createdWeek: doc.uploadedWeek, kind: doc.kind))
                changed = true
            }
        }

        if changed {
            state.digests = updated
            persist()
        }
    }

    /// Asks the model for one compact brief of a whole record. Best-effort: on any failure,
    /// or an empty brief, nothing is stored and the record's facts stand on their own.
    private func makeDigest(source: String, text: String) async -> String? {
        let user = "This is \(source). Brief it:\n\n\(text)"
        do {
            let raw = try await Runware.text(system: DIGEST_PROMPT,
                                             messages: [RunwareMessage(role: "user", content: user)],
                                             temperature: 0.2, maxTokens: 400)
            if let parsed = parseJsonLoose(raw),
               let brief = (parsed["brief"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !brief.isEmpty {
                return brief
            }
        } catch {
            // Best-effort; a failure must not lose the record — its facts already landed.
        }
        return nil
    }

    // MARK: - Consolidation

    /// Keeps Amber's working memory from piling up: facts older than the detail window
    /// fold into one general line per category, which the model reads instead of the raw
    /// entries. Additive and reversible — originals stay in `facts`, so the Memory screen
    /// is unchanged and scrubbing the week back still forgets honestly. Run just before
    /// instructions are built (voice connect, text reply), so scrubbing never thrashes it.
    func consolidateMemoryIfNeeded() async {
        guard !isConsolidating else { return }
        isConsolidating = true
        defer { isConsolidating = false }

        let oldCutoff = week - CONSOLIDATION_WINDOW_WEEKS
        // Usable, old, real facts — consent-filtered so we never summarise something she
        // has asked us not to keep.
        let usableOld = state.facts.filter { f in
            f.weekLearned <= oldCutoff && f.forgotten != true &&
            CONSOLIDATABLE_TYPES.contains(f.type) &&
            !(!state.consent.rememberPersonal && f.type == .personal)
        }

        var updated = state.consolidations
        var changed = false
        for type in CONSOLIDATABLE_TYPES {
            let group = usableOld.filter { $0.type == type }
            let ids = group.map { $0.id }.sorted()
            let existing = updated.first { $0.type == type }

            // A single old fact isn't worth generalising; leave any prior summary as-is.
            if group.count < 2 { continue }
            // Same cluster as last time: nothing to redo.
            if existing?.sourceFactIds.sorted() == ids { continue }

            guard let summary = await consolidateGroup(type: type, facts: group) else { continue }
            updated.removeAll { $0.type == type }
            updated.append(MemoryConsolidation(
                id: "cons-\(type.rawValue)",
                type: type,
                content: summary,
                throughWeek: group.map { $0.weekLearned }.max() ?? oldCutoff,
                sourceFactIds: ids,
                createdWeek: week))
            changed = true
        }

        if changed {
            state.consolidations = updated
            persist()
        }
    }

    /// Asks the model for one durable, general line summarising a cluster of older facts.
    /// Best-effort: on any failure the detailed facts simply stay in the prompt.
    private func consolidateGroup(type: FactType, facts: [MemoryFact]) async -> String? {
        let lines = facts.map { "- \($0.content)" }.joined(separator: "\n")
        let user = "Category: \(type.rawValue)\nOlder facts:\n\(lines)"
        do {
            let raw = try await Runware.text(system: CONSOLIDATION_PROMPT,
                                             messages: [RunwareMessage(role: "user", content: user)],
                                             temperature: 0.3, maxTokens: 200)
            if let parsed = parseJsonLoose(raw),
               let s = (parsed["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty {
                return s
            }
        } catch {
            // Best-effort; a failure must not drop the older facts from memory.
        }
        return nil
    }

    func clearHighlight() { lastAddedFactIds = [] }
}
