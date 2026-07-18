//
//  Digest.swift
//  AmberAI
//
//  The record-digest agent. The regex reader (Documents.swift) and the per-turn
//  extractor (AppState.commitExchange) each see records in fragments: a lab line here,
//  seven hand-picked consult facts there. This is the other half — an LLM pass over a
//  WHOLE record or the raw consult transcript, distilled into a short durable brief Amber
//  carries in her working memory.
//
//  It obeys the same law as the rest of the record path: TRANSCRIBE, NEVER INTERPRET.
//  It reads numbers back with any flag the source itself printed and never decides
//  whether a value is good, bad, in range, or worrying. Personal life is left out on
//  purpose — that flows through the consent-gated `.personal` facts, not here.
//

import Foundation

/// The programme week the Dr Patel consultation took place, so its digest is gated to
/// exactly the week the seven consult facts are learned (Consult.swift).
let CONSULT_WEEK = 4

let DIGEST_PROMPT = """
You compress a clinical record or a consultation transcript into a short, durable brief
that a NON-CLINICAL companion can carry in her working memory for weeks.

Write three to six short lines, each one clause, in the third person about the patient.
Capture what her prescriber told her: dose changes, instructions she was given, red-flag
warnings, follow-up plans, and any measured numbers exactly as they appear (including any
flag the lab itself printed, e.g. "LOW END").

Rules, in order of importance:
- TRANSCRIBE, NEVER INTERPRET. Never say a number is normal, high, low, good, bad, fine
  or worrying beyond a flag the source itself printed, and never explain what a result
  implies. Read it back, nothing more.
- Leave out her personal life outside the medical content. That is remembered elsewhere.
- Never invent anything that is not in the source. If the record is thin, write less.

Return strict JSON: {"brief":"line one\\nline two\\n..."}. If there is nothing worth
briefing, return {"brief":""}.
"""

/// The digests Amber may read at this week, oldest record first. Gated on `createdWeek`
/// so scrubbing back before a record arrived hides its brief, exactly like facts.
func recordsForPrompt(_ state: MemoryState, _ week: Int) -> String {
    let active = state.digests
        .filter { $0.createdWeek <= week && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .sorted { $0.createdWeek < $1.createdWeek }
    guard !active.isEmpty else { return "" }

    let blocks = active.map { "From \($0.sourceLabel):\n\($0.content)" }.joined(separator: "\n\n")
    return """
    WHAT HER RECORDS SAY
    \(blocks)

    This is read straight from her records and her consultations. You may remind her what \
    her prescriber actually said and read a number back exactly as it stands. You must not \
    interpret any result, say whether a value is good, bad or normal, or explain what it \
    means — that is her prescriber's to do, and you can offer to help her get it in front \
    of them.
    """
}
