//
//  Signposts.swift
//  AmberAI
//
//  A small curated directory of places Amber can point his toward. This is the same
//  idea as Safety.swift — a fixed signpost, not a clinical judgement — generalised from
//  crisis lines to partner services: a clinician finder, online therapy, a dietitian,
//  guided movement. Amber does not decide anyone needs treatment; he only names a door
//  when the person has already said he is looking for one. Choosing a door for someone
//  is help; deciding they need one would be a clinical call he is not qualified to make.
//
//  Deliberately restrained: one gentle offer when the person raises the need himself,
//  then drop it. Never a brand voice. The names and URLs below are configuration — swap
//  them for whichever partners are actually contracted.
//

import Foundation
import SwiftUI

/// The categories Amber can signpost. The raw values are the enum the model chooses from
/// when it calls the `suggest_resource` tool, so they must stay in sync with that tool.
enum SignpostCategory: String, CaseIterable, Hashable {
    case findDoctor = "find_doctor"
    case therapy
    case nutrition
    case movement
}

/// One door Amber can open. `whenToRaise` is guidance for the model; `tagline`, `cta`
/// and `url` are what the person actually sees and taps on the card.
struct Signpost: Identifiable, Hashable {
    let category: SignpostCategory
    /// The partner's name, spoken and shown. Kept human ("eMed", not "eMed Ltd.").
    let name: String
    /// One line on the card, plain and non-salesy.
    let tagline: String
    /// The button label.
    let cta: String
    /// Where the button goes.
    let url: URL
    /// Only used to brief the model on when this door is the right one to name.
    let whenToRaise: String
    /// SF Symbol + tint so each door has a glanceable identity on the card.
    let icon: String
    let tint: Color

    var id: String { category.rawValue }
}

/// The directory. One entry per category. Edit freely — nothing else hardcodes a partner.
let SIGNPOSTS: [SignpostCategory: Signpost] = [
    .findDoctor: Signpost(
        category: .findDoctor,
        name: "eMed",
        tagline: "See a clinician quickly, online, to move your care forward.",
        cta: "Find a clinician",
        url: URL(string: "https://www.emed.com")!,
        whenToRaise: "He says he wants a doctor, a prescriber, a second opinion, or is stuck getting clinical help to progress.",
        icon: "stethoscope",
        tint: Color(red: 0.30, green: 0.55, blue: 0.50)),

    .therapy: Signpost(
        category: .therapy,
        name: "BetterHelp",
        tagline: "Talk to a licensed therapist, from home, whenever suits you.",
        cta: "Explore therapy",
        url: URL(string: "https://www.betterhelp.com")!,
        whenToRaise: "He names low mood, anxiety, or wanting someone to talk to — and it is NOT a crisis (crisis is handled separately by the safety card).",
        icon: "cloud.rain.fill",
        tint: Color(red: 0.35, green: 0.52, blue: 0.72)),

    .nutrition: Signpost(
        category: .nutrition,
        name: "the BDA dietitian finder",
        tagline: "Find a registered dietitian for one-to-one food support.",
        cta: "Find a dietitian",
        url: URL(string: "https://freelance.bda.uk.com")!,
        whenToRaise: "He asks for real help with eating, appetite, or nutrition beyond what logging gives him.",
        icon: "leaf.fill",
        tint: Color(red: 0.30, green: 0.55, blue: 0.36)),

    .movement: Signpost(
        category: .movement,
        name: "Ascenti",
        tagline: "Guided physio and movement plans built around how you feel.",
        cta: "Get moving",
        url: URL(string: "https://www.ascenti.co.uk")!,
        whenToRaise: "He wants to get active, is worried about pain or strength, or asks where to start with movement.",
        icon: "figure.walk",
        tint: Theme.amber),
]

/// Look a door up from the id the model returned via the tool.
func resolveSignpost(_ raw: String) -> Signpost? {
    guard let category = SignpostCategory(rawValue: raw) else { return nil }
    return SIGNPOSTS[category]
}

/// The prompt block that tells Amber which doors exist and — the important part — how
/// sparingly to open them. Folded into buildInstructions.
func signpostsForPrompt() -> String {
    let doors = SignpostCategory.allCases.compactMap { SIGNPOSTS[$0] }.map {
        "  - \($0.name): \($0.tagline) Raise it only when: \($0.whenToRaise)"
    }.joined(separator: "\n")

    return """
    POINTING HER SOMEWHERE USEFUL
    You are not only a listener. When he tells you he is looking for help you cannot
    give, you can point his at a real door — and offer to put it on his screen. Use the
    suggest_resource tool to do that; a tappable card then appears while you speak.

    The doors you know:
    \(doors)

    How to do this without becoming a brand voice:
    - Only when SHE has named the need himself. Never fish for an opening, never upsell,
      never raise a service he did not ask toward. If in doubt, stay a listener.
    - One gentle offer, in your own words, then drop it. If he is not interested, leave it.
      Do not raise the same door twice in a conversation.
    - Name it as a suggestion, not an instruction: "there's a place I could show you", not
      "you should sign up".
    - This never replaces his prescriber, and it never overrides the safety card: if he is
      in crisis, that path takes over and you do not signpost a service instead.
    """
}
