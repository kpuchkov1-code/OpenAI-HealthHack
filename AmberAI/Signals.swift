//
//  Signals.swift
//  AmberAI
//
//  Derives "this member may need more support" from things the patient ACTUALLY SAID.
//  Every signal carries the fact ids it came from. Nothing here infers from vocal tone,
//  sentiment, or engagement telemetry. Ported from lib/signals.ts.
//

import Foundation

private let STRUGGLE_THRESHOLD = 0.7
private let STRUGGLE_WINDOW_WEEKS = 2
private let ONBOARDING_WEEKS = 2

func deriveSignals(_ state: MemoryState, _ week: Int) -> [SupportSignal] {
    // The refusal is total, checked here rather than at the screen. Nothing downstream
    // of this line executes.
    if !state.consent.shareWithClinician { return [] }

    // factsForPrompt, not factsAsOf: a forgotten fact must not reappear as a flag.
    let facts = factsForPrompt(state.facts, week, state.consent)
    var signals: [SupportSignal] = []

    let struggles = facts.filter {
        $0.type == .struggle && $0.salience >= STRUGGLE_THRESHOLD && $0.weekLearned > week - STRUGGLE_WINDOW_WEEKS
    }
    if week > ONBOARDING_WEEKS && struggles.count >= 2 {
        signals.append(SupportSignal(
            label: "Has said out loud that he is finding it hard",
            detail: struggles.prefix(3).map { "\"\($0.content)\" (week \($0.weekLearned))" }.joined(separator: "  ·  "),
            sourceFactIds: struggles.map { $0.id },
            severity: .support))
    }

    let quiet = daysSinceLastContact(week)
    if quiet >= 5 {
        signals.append(SupportSignal(
            label: "No contact for \(quiet) days",
            detail: "Amber has reached out. No reply yet. Previous silence preceded a missed dose.",
            sourceFactIds: [],
            severity: quiet >= 10 ? .support : .watch))
    }

    let symptoms = facts.filter { $0.type == .symptom && $0.salience >= 0.75 }
    if symptoms.count >= 2 {
        signals.append(SupportSignal(
            label: "Persistent side effects reported",
            detail: symptoms.prefix(3).map { "\"\($0.content)\"" }.joined(separator: "  ·  "),
            sourceFactIds: symptoms.map { $0.id },
            severity: .watch))
    }

    let instructions = facts.filter { $0.type == .clinicalInstruction }
    if !instructions.isEmpty {
        signals.append(SupportSignal(
            label: "\(instructions.count) instructions from his prescriber in memory",
            detail: "Amber can support him around these between appointments.",
            sourceFactIds: instructions.map { $0.id },
            severity: .watch))
    }

    return signals
}

enum SupportVerdict: String { case steady, watch, support }

func supportVerdict(_ signals: [SupportSignal]) -> SupportVerdict {
    if signals.contains(where: { $0.severity == .support }) { return .support }
    if !signals.isEmpty { return .watch }
    return .steady
}
