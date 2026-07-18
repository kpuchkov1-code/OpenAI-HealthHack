//
//  Documents.swift
//  AmberAI
//
//  Reading records into memory. The hard rule: TRANSCRIBE, NEVER INTERPRET. We echo
//  the numbers and any flag the lab itself printed. We never decide whether a value
//  is good, bad, in range, or worrying. Ported from lib/documents.ts.
//

import Foundation

struct ParsedFact {
    let type: FactType
    let content: String
    let salience: Double
}

func classifyKind(name: String, text: String) -> DocumentKind {
    let hay = "\(name)\n\(text)".lowercased()
    if matches(#"\b(ref|reference range|mmol/mol|u/l|ug/l|g/l|haemoglobin|ferritin|hba1c)\b"#, hay) {
        return .bloodPanel
    }
    if matches(#"\b(prescription|dispense|mg/ml pen|repeat medication)\b"#, hay) { return .prescription }
    if matches(#"\b(dear|yours sincerely|clinic letter|discharge)\b"#, hay) { return .letter }
    return .other
}

// A lab result line, e.g.  Ferritin  18 ug/L  (ref 15-150)  LOW END
private let RESULT_LINE = #"^\s*([A-Za-z][A-Za-z0-9 /()'-]{1,30}?)\s{2,}([<>]?[\d.]+)\s*([A-Za-z%/µu]*[A-Za-z%/]|)\s*\(ref\s*([^)]+)\)\s*(.*)$"#
private let COMMENT_LINE = #"^\s*(?:comment|advice|action|plan)s?\s*:\s*(.+)$"#
private let COLLECTED = #"\b(?:collected|taken|sample date|date)\s*:\s*([\d]{1,2}[/-][\d]{1,2}[/-][\d]{2,4})"#

/// Deterministic reader. No model, no key, no network. For a structured lab panel it
/// is strictly better than an LLM: it cannot fabricate a value that was never printed.
func parseDocument(_ text: String) -> [ParsedFact] {
    let date = firstGroup(COLLECTED, text, options: [.caseInsensitive])
    let on = date.map { " on \($0)" } ?? ""
    var facts: [ParsedFact] = []

    for raw in text.components(separatedBy: .newlines) {
        if let g = groups(RESULT_LINE, raw), g.count >= 6 {
            let name = g[1].trimmingCharacters(in: .whitespaces)
            let value = g[2]
            let unit = g[3].trimmingCharacters(in: .whitespaces)
            let ref = g[4].trimmingCharacters(in: .whitespaces)
            let flag = g[5].trimmingCharacters(in: .whitespaces)
            let measure = unit.isEmpty ? value : "\(value) \(unit)"
            let flagged = flag.isEmpty ? "" : ", flagged \"\(flag)\" by the lab"
            facts.append(ParsedFact(
                type: .symptom,
                content: "\(name) \(measure)\(on) (lab range \(ref))\(flagged)",
                salience: flag.isEmpty ? 0.5 : 0.7))
            continue
        }
        if let g = groups(COMMENT_LINE, raw, options: [.caseInsensitive]), g.count >= 2 {
            facts.append(ParsedFact(
                type: .clinicalInstruction,
                content: "Lab comment\(on): \(g[1].trimmingCharacters(in: .whitespaces))",
                salience: 0.75))
        }
    }
    return facts
}

// MARK: - Regex helpers

func matches(_ pattern: String, _ text: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> Bool {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
    return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}

/// Returns full-match at index 0 followed by capture groups. Empty groups become "".
func groups(_ pattern: String, _ text: String, options: NSRegularExpression.Options = []) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options),
          let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    var out: [String] = []
    for i in 0..<m.numberOfRanges {
        if let r = Range(m.range(at: i), in: text) {
            out.append(String(text[r]))
        } else {
            out.append("")
        }
    }
    return out
}

func firstGroup(_ pattern: String, _ text: String, options: NSRegularExpression.Options = []) -> String? {
    guard let g = groups(pattern, text, options: options), g.count >= 2 else { return nil }
    return g[1]
}
