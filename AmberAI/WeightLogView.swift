//
//  WeightLogView.swift
//  AmberAI
//
//  The weigh-in sheet, reached from the Progress tab. One decimal field, a day picker,
//  an optional note — the same shape as food logging's confirm screen, so the two ways
//  of recording a day feel like one app. Saved entries feed the trend and the calendar.
//

import SwiftUI

struct WeightLogView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    @State private var kgText = ""
    @State private var day = 0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    weightCard
                    dayCard
                    noteCard
                    if let prev = app.currentWeight {
                        Label("Last weigh-in: \(foodNum(prev.kg)) kg · week \(prev.week)",
                              systemImage: "clock.arrow.circlepath")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding()
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(parsedKg == nil)
                }
            }
            .onAppear {
                if kgText.isEmpty, let w = app.currentWeight { kgText = foodNum(w.kg) }
            }
        }
        .tint(Theme.amber)
    }

    // MARK: - Weight entry

    /// A big, centred number with quick −/+ 0.1 kg nudges either side, so a small
    /// change never needs the keyboard.
    private var weightCard: some View {
        VStack(spacing: 14) {
            Text("Current weight")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 18) {
                nudgeButton(symbol: "minus", delta: -0.1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("0.0", text: $kgText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .fixedSize()
                    Text("kg")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                nudgeButton(symbol: "plus", delta: 0.1)
            }
            .frame(maxWidth: .infinity)
        }
        .cardBackground()
    }

    private func nudgeButton(symbol: String, delta: Double) -> some View {
        Button {
            step(delta)
        } label: {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.amberSoft.opacity(0.3)))
                .foregroundStyle(Theme.amber)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day

    private var dayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which day?")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    dayPill(i)
                }
            }

            Text("Week \(app.week), \(fullDay(day))")
                .font(.caption).foregroundStyle(.secondary)

            if weightForDay(app.state.weightEntries, app.week, day) != nil {
                Label("You already weighed in this day. Saving replaces it.",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(Theme.watch)
            }
        }
        .cardBackground()
    }

    private func dayPill(_ i: Int) -> some View {
        let selected = day == i
        return Button {
            day = i
        } label: {
            Text(dayLabels[i])
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? Theme.amber : Theme.amberSoft.opacity(0.22))
                )
                .foregroundStyle(selected ? .white : Theme.ink)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Note

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Note (optional)")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Anything you want to remember about it", text: $note, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
        }
        .cardBackground()
    }

    /// Nudge the weight by ±0.1 kg, rounding to one decimal so the field stays tidy.
    private func step(_ delta: Double) {
        let base = parsedKg ?? app.currentWeight?.kg ?? 0
        let v = max(0, (base + delta) * 10).rounded() / 10
        kgText = foodNum(v)
    }

    /// A plausible weight in kilograms, or nil while the field is empty or nonsense.
    private var parsedKg: Double? {
        let cleaned = kgText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(cleaned), v > 0, v < 500 else { return nil }
        return v
    }

    private func fullDay(_ i: Int) -> String {
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][i]
    }

    private func save() {
        guard let kg = parsedKg else { return }
        app.addWeight(kg: kg, day: day, note: note)
        dismiss()
    }
}
