//
//  Components.swift
//  AmberAI
//
//  Shared styling and small reusable views: the theme, the week scrubber (the "time
//  is honest" control), the safety card, and fact type/source labelling.
//

import SwiftUI

enum Theme {
    static let amber = Color(red: 0.85, green: 0.61, blue: 0.13)
    static let amberSoft = Color(red: 0.97, green: 0.85, blue: 0.58)
    static let bg = Color(red: 0.99, green: 0.975, blue: 0.95)
    static let ink = Color(red: 0.16, green: 0.13, blue: 0.11)
    static let support = Color(red: 0.80, green: 0.30, blue: 0.24)
    static let watch = Color(red: 0.82, green: 0.60, blue: 0.16)
    static let steady = Color(red: 0.30, green: 0.55, blue: 0.36)
}

extension FactType {
    var display: String {
        switch self {
        case .symptom: return "Symptom"
        case .medication: return "Medication"
        case .clinicalInstruction: return "Clinical"
        case .personal: return "Personal"
        case .struggle: return "Struggle"
        }
    }
    var tint: Color {
        switch self {
        case .symptom: return Color(red: 0.35, green: 0.52, blue: 0.72)
        case .medication: return Color(red: 0.55, green: 0.40, blue: 0.70)
        case .clinicalInstruction: return Color(red: 0.30, green: 0.55, blue: 0.50)
        case .personal: return Theme.amber
        case .struggle: return Theme.support
        }
    }
    /// SF Symbol used to give each memory category a glanceable identity.
    var icon: String {
        switch self {
        case .symptom: return "waveform.path.ecg"
        case .medication: return "pills.fill"
        case .clinicalInstruction: return "stethoscope"
        case .personal: return "person.fill"
        case .struggle: return "cloud.rain.fill"
        }
    }
}

extension FactSource {
    var display: String {
        switch self {
        case .conversation: return "he told Amber"
        case .consult: return "Dr Patel consult"
        case .document: return "from a record"
        case .habit: return "habit"
        case .consolidated: return "summarised"
        }
    }
}

/// A small rounded tag.
struct Tag: View {
    let text: String
    var color: Color = Theme.amber
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// The scrubber. Drag it back and Amber genuinely forgets, because every screen reads
/// the same `app.week`. This is the demo's opening beat.
struct WeekScrubber: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Week \(app.week)")
                    .font(.headline)
                Spacer()
                Text(app.weekLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(app.week) },
                    set: { app.week = Int($0.rounded()) }),
                in: Double(app.minWeek)...Double(app.maxWeek),
                step: 1)
            .tint(Theme.amber)
            HStack {
                Text("Week \(app.minWeek)").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if app.quietDays >= 5 {
                    Text("\(app.quietDays) days quiet")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.support)
                }
                Spacer()
                Text("Week \(app.maxWeek)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.amberSoft.opacity(0.5)))
    }
}

/// The static safety signpost. No severity assessment; a fixed card on a trigger.
struct SafetyCardView: View {
    let hit: SafetyHit
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hit.card.title).font(.headline)
            Text(hit.card.body).font(.subheadline)
            HStack(spacing: 12) {
                Link(destination: URL(string: "tel://\(hit.card.number.replacingOccurrences(of: " ", with: ""))")!) {
                    Label("\(hit.card.action) · \(hit.card.number)", systemImage: "phone.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.support, in: Capsule())
                        .foregroundStyle(.white)
                }
                Spacer()
                Button("Dismiss", action: onDismiss)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Theme.support.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.support.opacity(0.4)))
    }
}

/// The proactive signpost. Not a diagnosis and not an ad — a door Amber offers when the
/// person has already said she's looking for one. Same shape as the safety card, tinted
/// to the resource rather than to alarm.
struct SignpostCardView: View {
    let signpost: Signpost
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: signpost.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(signpost.tint)
                Text(signpost.name).font(.headline)
            }
            Text(signpost.tagline).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Link(destination: signpost.url) {
                    Label(signpost.cta, systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(signpost.tint, in: Capsule())
                        .foregroundStyle(.white)
                }
                Spacer()
                Button("Not now", action: onDismiss)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(signpost.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(signpost.tint.opacity(0.4)))
    }
}
