//
//  FoodLogView.swift
//  AmberAI
//
//  The food-logging sheet, reached from Habits. Four ways in — scan a barcode, search
//  the database, describe it, or hand over a photo — all funnel into one confirm screen
//  where she edits the label, picks the day, and saves. Saved entries feed the same
//  food maths the Habits circles and Amber's prompt already read.
//

import SwiftUI
import PhotosUI
import UIKit

private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

func foodNum(_ d: Double) -> String {
    d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
}

struct FoodLogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { BarcodeFlow(close: close) } label: {
                        methodRow("barcode.viewfinder", "Scan a barcode", "Point the camera at a label")
                    }
                    NavigationLink { SearchFlow(close: close) } label: {
                        methodRow("magnifyingglass", "Search the food database", "Open Food Facts, by name")
                    }
                    NavigationLink { DescribeFlow(close: close) } label: {
                        methodRow("text.bubble", "Describe it to Amber", "Say what you ate, get an estimate")
                    }
                    NavigationLink { PhotoFlow(close: close) } label: {
                        methodRow("camera", "Analyse a photo", "Estimate from a picture of the meal")
                    }
                } header: {
                    Text("How do you want to log it?")
                } footer: {
                    Text("A barcode or a search reads real label data. A description or a photo is Amber's estimate, and lands marked as one.")
                }
            }
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(Theme.amber)
    }

    /// Captured at the sheet root, so any confirm screen can close the whole sheet.
    private func close() { dismiss() }

    private func methodRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(Theme.amber)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Barcode

private struct BarcodeFlow: View {
    let close: () -> Void
    @State private var draft: FoodDraft?
    @State private var status: String?
    @State private var looking = false

    var body: some View {
        Group {
            if BarcodeScannerView.isSupported {
                ZStack(alignment: .bottom) {
                    BarcodeScannerView { code in Task { await lookup(code) } }
                        .ignoresSafeArea(edges: .bottom)
                    if let status {
                        Text(status)
                            .font(.subheadline.weight(.medium))
                            .padding(12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 24)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No camera here",
                    systemImage: "camera.fill",
                    description: Text("Barcode scanning needs a device with a camera. Try search or describe instead."))
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $draft) { ConfirmView(draft: $0, close: close) }
    }

    private func lookup(_ code: String) async {
        guard !looking, draft == nil else { return }
        looking = true
        status = "Looking up \(code)…"
        do {
            if let d = try await OpenFoodFacts.lookup(barcode: code) {
                draft = d
            } else {
                status = "No match for \(code). Try search or describe."
            }
        } catch {
            status = (error as? RunwareError)?.message ?? "Lookup failed."
        }
        looking = false
    }
}

// MARK: - Search

private struct SearchFlow: View {
    let close: () -> Void
    @State private var query = ""
    @State private var results: [FoodDraft] = []
    @State private var searching = false
    @State private var message: String?
    @State private var draft: FoodDraft?

    var body: some View {
        List {
            if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
            ForEach(results) { r in
                Button { draft = r } label: { resultRow(r) }
                    .buttonStyle(.plain)
            }
        }
        .overlay { if searching { ProgressView().controlSize(.large) } }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "e.g. Greek yogurt")
        .onSubmit(of: .search) { Task { await run() } }
        .navigationTitle("Search foods")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $draft) { ConfirmView(draft: $0, close: close) }
    }

    private func resultRow(_ r: FoodDraft) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(r.label).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
            if let p = r.nutrition?.proteinG {
                Text("\(foodNum(p)) g protein / 100 g").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No nutrition on file").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searching = true; message = nil; results = []
        do {
            let found = try await OpenFoodFacts.search(q)
            results = found
            if found.isEmpty { message = "Nothing found for “\(q)”." }
        } catch {
            message = (error as? RunwareError)?.message ?? "Search failed."
        }
        searching = false
    }
}

// MARK: - Describe

private struct DescribeFlow: View {
    let close: () -> Void
    @State private var text = ""
    @State private var working = false
    @State private var error: String?
    @State private var draft: FoodDraft?
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                TextField("e.g. a bowl of porridge with berries and a spoon of peanut butter",
                          text: $text, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focused)
            } header: {
                Text("What did you eat?")
            } footer: {
                Text("Amber estimates the nutrition. It lands in the log marked as an estimate, not a label.")
            }
            Section {
                Button {
                    focused = false
                    Task { await estimate() }
                } label: {
                    HStack {
                        Text("Estimate with Amber")
                        Spacer()
                        if working { ProgressView() }
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(Theme.support) }
            }
        }
        .navigationTitle("Describe")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $draft) { ConfirmView(draft: $0, close: close) }
        .onAppear { focused = true }
    }

    private func estimate() async {
        working = true; error = nil
        do {
            draft = try await FoodAI.fromDescription(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            self.error = (error as? RunwareError)?.message ?? "Estimate failed."
        }
        working = false
    }
}

// MARK: - Photo

private struct PhotoFlow: View {
    let close: () -> Void
    @State private var pick: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var working = false
    @State private var error: String?
    @State private var draft: FoodDraft?

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $pick, matching: .images) {
                    Label(image == nil ? "Choose a photo" : "Choose a different photo", systemImage: "photo")
                }
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } footer: {
                Text("Amber estimates the nutrition from the picture. It lands marked as an estimate.")
            }
            if image != nil {
                Section {
                    Button {
                        Task { await analyse() }
                    } label: {
                        HStack {
                            Text("Analyse this photo")
                            Spacer()
                            if working { ProgressView() }
                        }
                    }
                    .disabled(working)
                }
            }
            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(Theme.support) }
            }
        }
        .navigationTitle("Photo")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $draft) { ConfirmView(draft: $0, close: close) }
        .onChange(of: pick) { _, new in
            guard let new else { return }
            Task {
                if let data = try? await new.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    image = ui
                    error = nil
                }
            }
        }
    }

    private func analyse() async {
        guard let image, let jpeg = downscaled(image).jpegData(compressionQuality: 0.6) else { return }
        working = true; error = nil
        do {
            draft = try await FoodAI.fromImage(jpeg)
        } catch {
            self.error = (error as? RunwareError)?.message ?? "Analysis failed."
        }
        working = false
    }

    /// Keep the base64 payload sane before it rides in a JSON request.
    private func downscaled(_ image: UIImage, maxDimension: CGFloat = 1024) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Confirm & save

private struct ConfirmView: View {
    @EnvironmentObject var app: AppState
    let draft: FoodDraft
    let close: () -> Void

    @State private var label: String
    @State private var day: Int
    @State private var note: String

    init(draft: FoodDraft, close: @escaping () -> Void) {
        self.draft = draft
        self.close = close
        _label = State(initialValue: draft.label)
        _note = State(initialValue: draft.note ?? "")
        _day = State(initialValue: 0)
    }

    var body: some View {
        Form {
            Section("Food") {
                TextField("Name", text: $label, axis: .vertical)
                if draft.estimated == true {
                    Label("Amber's estimate, not a label.", systemImage: "sparkles")
                        .font(.caption).foregroundStyle(Theme.amber)
                }
            }

            if let n = draft.nutrition, n.hasAnyValue {
                Section {
                    nutritionRow("Calories", n.kcal, unit: "kcal")
                    nutritionRow("Protein", n.proteinG, unit: "g")
                    nutritionRow("Carbs", n.carbsG, unit: "g")
                    nutritionRow("Fat", n.fatG, unit: "g")
                    nutritionRow("Fibre", n.fibreG, unit: "g")
                } header: {
                    Text("Nutrition")
                } footer: {
                    Text(n.basis == "per_100g" ? "Per 100 g, from the label." : "For the portion, estimated.")
                }
            }

            Section("Which day?") {
                Picker("Day", selection: $day) {
                    ForEach(0..<7, id: \.self) { i in Text(dayLabels[i]).tag(i) }
                }
                .pickerStyle(.segmented)
                Text("Week \(app.week), \(fullDay(day))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Note (optional)") {
                TextField("Anything you want to remember about it", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }

            Section {
                LabeledContent("Source", value: draft.provenance)
                    .font(.caption)
            }
        }
        .navigationTitle("Confirm")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func nutritionRow(_ name: String, _ value: Double?, unit: String) -> some View {
        LabeledContent(name, value: value.map { "\(foodNum($0)) \(unit)" } ?? "—")
    }

    private func fullDay(_ i: Int) -> String {
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][i]
    }

    private func save() {
        var d = draft
        d.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        d.note = trimmedNote.isEmpty ? nil : trimmedNote
        app.addFood(d, day: day)
        close()
    }
}

private extension FoodNutrition {
    var hasAnyValue: Bool { kcal != nil || proteinG != nil || carbsG != nil || fatG != nil || fibreG != nil }
}
