//
//  Safety.swift
//  AmberAI
//
//  Deliberately dumb: a fixed keyword match to a fixed signpost. There is no model
//  here on purpose. Assessing the SEVERITY of distress is a clinical task; a static
//  signpost on a trigger is referral advice, which is not. Ported from lib/safety.ts.
//

import Foundation

struct SafetyCard: Hashable {
    let title: String
    let body: String
    let action: String
    let number: String
}

struct SafetyHit: Hashable {
    enum Kind: String { case crisis, clinical }
    let kind: Kind
    let card: SafetyCard
}

// Err generously. A false positive costs one dismissed card; a false negative costs
// something we cannot undo. Note the gerunds ("killing myself") and the deliberate
// absence of bare "kill me" (overwhelmingly idiomatic).
private let CRISIS_PATTERNS: [String] = [
    #"\bkill(ing)? myself\b"#,
    #"\btake?(ing)? my own life\b"#,
    #"\bend (it all|it|my life)\b"#,
    #"\bending (it all|my life)\b"#,
    #"\bsuicid"#,
    #"\bself[- ]harm"#,
    #"\bharm(ing)? myself\b"#,
    #"\bhurt(ing)? myself\b"#,
    #"\bcut(ting)? myself\b"#,
    #"\bdon'?t want to (be here|live|wake up|go on|exist)\b"#,
    #"\bwant to die\b"#,
    #"\bwish I (was|were) dead\b"#,
    #"\bno point (in )?(living|going on|carrying on|any ?more)\b"#,
    #"\bbetter off without me\b"#,
    #"\bcan'?t (do|take) this any ?more\b"#,
]

private let CLINICAL_RED_FLAGS: [String] = [
    #"\bsevere (abdominal|stomach|belly) pain\b"#,
    #"\bpain .{0,20}(radiat|spread)"#,
    #"\bcan'?t stop (being sick|vomiting|throwing up)\b"#,
    #"\bvomiting blood\b"#,
    #"\bchest pain\b"#,
]

private let CRISIS_CARD = SafetyCard(
    title: "This needs a person, not me",
    body: "I am not able to help with this, and I am not going to pretend otherwise. Please talk to someone now.",
    action: "Samaritans, free, 24 hours",
    number: "116 123")

private let CLINICAL_CARD = SafetyCard(
    title: "Please contact your care team",
    body: "What you have described is something your prescriber told you to report urgently. Do not wait for me.",
    action: "NHS urgent advice",
    number: "111")

private func matchesAny(_ patterns: [String], _ text: String) -> Bool {
    let range = NSRange(text.startIndex..., in: text)
    for p in patterns {
        if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
           re.firstMatch(in: text, options: [], range: range) != nil {
            return true
        }
    }
    return false
}

func checkSafety(_ text: String) -> SafetyHit? {
    if matchesAny(CRISIS_PATTERNS, text) {
        return SafetyHit(kind: .crisis, card: CRISIS_CARD)
    }
    if matchesAny(CLINICAL_RED_FLAGS, text) {
        return SafetyHit(kind: .clinical, card: CLINICAL_CARD)
    }
    return nil
}

/// The spoken/typed reply Amber gives when a safety trigger fires, before any model
/// sees the message. Mirrors app/api/chat/route.ts.
func safetyReply(_ hit: SafetyHit) -> String {
    switch hit.kind {
    case .crisis:
        return "I want to stop here, because this is bigger than me and you deserve someone who can actually help."
    case .clinical:
        return "That is one of the things Dr Patel told you to report straight away. Please ring them now rather than waiting for me."
    }
}
