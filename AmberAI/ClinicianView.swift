//
//  ClinicianView.swift
//  AmberAI
//
//  The eMed screen. A different product: no companion, no tone analysis. Every flag
//  traces to something she said in words, and carries the fact ids it came from. When
//  she switches off "share support signals", deriveSignals returns [] on line one and
//  this screen is dark — not hidden, unscored.
//

import SwiftUI

struct ClinicianView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    patientHeader

                    if !app.state.consent.shareWithClinician {
                        consentOff
                    } else {
                        verdictBanner
                        ForEach(app.signals) { signal in
                            signalCard(signal)
                        }
                        if app.signals.isEmpty {
                            Text("No support signals at week \(app.week). Nothing to action.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        provenanceNote
                    }
                }
                .padding()
            }
            .background(Color(red: 0.09, green: 0.10, blue: 0.12).ignoresSafeArea())
            .navigationTitle("eMed · Care team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.amberSoft)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var patientHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Patient.name).font(.title2.weight(.bold)).foregroundStyle(.white)
            Text("\(Patient.age) · \(Patient.medication) · \(Patient.prescriber) · week \(app.week)")
                .font(.caption).foregroundStyle(.gray)
        }
    }

    private var consentOff: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "eye.slash").font(.title).foregroundStyle(.gray)
            Text("He has switched off sharing support signals with his care team.")
                .font(.headline).foregroundStyle(.white)
            Text("Nothing is scored here — not merely hidden. His care is unchanged. This is the one feature eMed is paying for, and he can refuse it without losing anything else.")
                .font(.subheadline).foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private var verdictBanner: some View {
        let v = app.verdict
        let (label, color): (String, Color) = {
            switch v {
            case .support: return ("Needs support", Theme.support)
            case .watch: return ("Worth a watch", Theme.watch)
            case .steady: return ("Steady", Theme.steady)
            }
        }()
        return HStack {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(label).font(.headline).foregroundStyle(.white)
            Spacer()
            Text("\(app.signals.count) signal\(app.signals.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.gray)
        }
        .padding(14)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.5)))
    }

    private func signalCard(_ signal: SupportSignal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(signal.label).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Tag(text: signal.severity.rawValue,
                    color: signal.severity == .support ? Theme.support : Theme.watch)
            }
            Text(signal.detail).font(.footnote).foregroundStyle(.gray)
            if !signal.sourceFactIds.isEmpty {
                Text("Traces to: \(signal.sourceFactIds.joined(separator: ", "))")
                    .font(.caption2.monospaced()).foregroundStyle(Theme.amberSoft.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private var provenanceNote: some View {
        Text("Every flag is derived from a fact the patient stated in words, never from vocal tone, sentiment, or engagement telemetry. A concern he stated is care; a churn score from his voice would be a different, and unlawful, product.")
            .font(.caption).foregroundStyle(.gray)
            .padding(.top, 4)
    }
}
