//
//  RecordsView.swift
//  AmberAI
//
//  Records transcribe, they never interpret. A lab panel is read by a regex, so it
//  cannot hallucinate a value that was never printed; the extracted fact sits beside
//  the source it came from. The week-4 consult lands its clinical facts here too.
//
//  Real records come in as files, not just pasted text: a PDF from eMed or a GP, a
//  photo of a paper letter. RecordReader turns any of those into text on-device, then
//  the same deterministic reader runs. Nothing leaves the phone to read a record.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct RecordsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var account: AccountStore
    @State private var showConsult = false
    @State private var showLiveConsult = false
    @State private var showReport = false
    @State private var selectedDoc: PatientDocument?
    @State private var pasteName = ""
    @State private var pasteText = ""
    @State private var showPaste = false

    // Importing a real file.
    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var importError: String?

    // The doctor report, rendered to a branded PDF on disk and re-rendered whenever the
    // data behind it changes (the week scrubs, a record lands, a wearable refreshes).
    @State private var reportURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    consultCard
                    liveConsultCard
                    doctorReportCard
                    documentsSection
                    addRecordCard
                }
                .padding()
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Records")
            .sheet(isPresented: $showConsult) { consultSheet }
            .sheet(isPresented: $showLiveConsult) { LiveConsultView() }
            .sheet(isPresented: $showReport) { reportSheet }
            .sheet(item: $selectedDoc) { doc in documentSheet(doc) }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: RecordReader.importableTypes,
                allowsMultipleSelection: true,
                onCompletion: handleImportedFiles)
            .onChange(of: photoItem) { _, item in handlePhoto(item) }
        }
    }

    // MARK: - Consult

    private var consultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Consult with Dr Patel", systemImage: "stethoscope")
                    .font(.headline)
                Spacer()
                Tag(text: "week 4", color: Theme.amber)
            }
            Text("The week-4 review. Stepping up to 5mg, protein, the jab-at-night tip, and the red-flag warning.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    showConsult = true
                } label: {
                    Label("Read transcript", systemImage: "text.bubble")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                if app.consultIngested {
                    Label("\(CONSULT_FACTS.count) facts in memory", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(Theme.steady)
                } else {
                    Button {
                        withAnimation { app.ingestConsult() }
                    } label: {
                        Text("Add to memory")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Theme.amber, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .cardBackground()
    }

    private var consultSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(CONSULT_TRANSCRIPT) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.speaker)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(line.speaker == "Dr Patel" ? Theme.amber : Theme.ink)
                            Text(line.text).font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Dr Patel consult")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Live consult (Amber sits in)

    private var liveConsultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Amber joins your appointment", systemImage: "person.2.wave.2")
                    .font(.headline)
                Spacer()
                Tag(text: "live", color: Theme.support)
            }
            Text("Paste your meeting link and Amber joins the call as a note-taker. It transcribes the conversation and pulls the medication, instructions and any red flags straight into your records — you just talk to your doctor.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                showLiveConsult = true
            } label: {
                Label("Join a call", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.amber, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .cardBackground()
    }

    // MARK: - Doctor report

    private var reportPatientName: String {
        account.profile.fullName.isEmpty ? Patient.name : account.profile.fullName
    }

    /// (Re)render the PDF for the current week, profile and live wearable snapshots.
    private func regenerateReport() {
        reportURL = DoctorReportPDF.render(
            state: app.state, week: app.week,
            profile: account.profile, wearables: app.wearableSummaries)
    }

    private var doctorReportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Report for your doctor", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            Text("A formatted PDF you can hand to your prescriber: your weight, nutrition and habits, anything your wearables report, and the treatment notes from your records and consults. The personal things you tell Amber in chat are left out.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    showReport = true
                } label: {
                    Label("Preview", systemImage: "eye")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                if let reportURL {
                    ShareLink(item: reportURL,
                              preview: SharePreview("Amber report for \(reportPatientName)",
                                                    image: Image(systemName: "doc.richtext"))) {
                        Label("Export PDF", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Theme.amber, in: Capsule())
                            .foregroundStyle(.white)
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .cardBackground()
        .onAppear { regenerateReport() }
        .onChange(of: app.week) { _, _ in regenerateReport() }
        .onChange(of: app.state.documents.count) { _, _ in regenerateReport() }
        .onChange(of: app.wearableSummaries) { _, _ in regenerateReport() }
    }

    private var reportSheet: some View {
        NavigationStack {
            Group {
                if let reportURL {
                    PDFKitView(url: reportURL)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("Preparing the report…", systemImage: "doc.richtext")
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Doctor report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let reportURL {
                        ShareLink(item: reportURL,
                                  preview: SharePreview("Amber report for \(reportPatientName)",
                                                        image: Image(systemName: "doc.richtext"))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .tint(Theme.amber)
                    }
                }
            }
            .onAppear { if reportURL == nil { regenerateReport() } }
        }
    }

    // MARK: - Documents

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DOCUMENTS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            ForEach(app.state.documents) { doc in
                Button { selectedDoc = doc } label: {
                    HStack {
                        Image(systemName: icon(for: doc.kind))
                            .foregroundStyle(Theme.amber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                            Text("\(doc.factIds.count) facts · week \(doc.uploadedWeek)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .cardBackground()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func icon(for kind: DocumentKind) -> String {
        switch kind {
        case .bloodPanel: return "drop.fill"
        case .letter: return "envelope"
        case .prescription: return "pills"
        case .other: return "doc.text"
        }
    }

    private func documentSheet(_ doc: PatientDocument) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WHAT AMBER READ").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        Text(doc.text)
                            .font(.system(.footnote, design: .monospaced))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FACTS IT TRANSCRIBED").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        if app.factsFor(document: doc).isEmpty {
                            Text("Amber read this record but found no structured results to transcribe. The full text is kept above exactly as it arrived.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(app.factsFor(document: doc)) { fact in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fact.content).font(.subheadline)
                                Tag(text: fact.type.display, color: fact.type.tint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Theme.amberSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                        }
                        Text("It echoes the numbers and any flag the lab printed. It never says whether a value is good, bad, or worrying — that is a clinical act.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(doc.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Add a record

    private var addRecordCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADD A RECORD").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text("A PDF from eMed or your GP, a photo of a letter, or plain text. Amber reads it on your phone — nothing is uploaded — and transcribes the numbers. It never decides what they mean.")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 10) {
                importButton
                photoButton
            }

            Button {
                withAnimation { showPaste.toggle() }
            } label: {
                Label(showPaste ? "Hide text box" : "Paste text instead", systemImage: "text.cursor")
                    .font(.subheadline.weight(.semibold))
            }

            if showPaste { pasteEditor }

            if isReading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reading the record…").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardBackground()
    }

    private var importButton: some View {
        Button {
            importError = nil
            showFileImporter = true
        } label: {
            Label("Import file", systemImage: "doc.badge.plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.amberSoft.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isReading)
    }

    private var photoButton: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Label("Add photo", systemImage: "photo.badge.plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.amberSoft.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        }
        .disabled(isReading)
    }

    private var pasteEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name (optional)", text: $pasteName)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $pasteText)
                .frame(height: 140)
                .padding(6)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.amberSoft.opacity(0.5)))
            HStack {
                Button("Use the sample panel") { pasteText = Self.samplePanel; pasteName = "Bloods.txt" }
                    .font(.caption)
                Spacer()
                Button {
                    app.addDocument(name: pasteName, text: pasteText)
                    pasteText = ""; pasteName = ""
                    showPaste = false
                } label: {
                    Text("Read it").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.amber, in: Capsule())
                        .foregroundStyle(.white)
                }
                .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Import handling

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            // Read each file's bytes while its security scope is held, then release it.
            var payloads: [(name: String, data: Data, type: UTType?)] = []
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { continue }
                payloads.append((url.lastPathComponent, data, UTType(filenameExtension: url.pathExtension)))
            }
            guard !payloads.isEmpty else {
                importError = "Amber couldn't open that file."
                return
            }
            readAndAdd(payloads)
        }
    }

    private func readAndAdd(_ payloads: [(name: String, data: Data, type: UTType?)]) {
        isReading = true
        importError = nil
        Task {
            var firstError: String?
            for p in payloads {
                do {
                    let text = try await RecordReader.extractText(name: p.name, data: p.data, utType: p.type)
                    app.addDocument(name: p.name, text: text)
                } catch {
                    if firstError == nil { firstError = message(for: error, name: p.name) }
                }
            }
            isReading = false
            importError = firstError
        }
    }

    private func handlePhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isReading = true
        importError = nil
        Task {
            defer { photoItem = nil; isReading = false }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                importError = "That photo couldn't be loaded."
                return
            }
            do {
                let text = try await RecordReader.extractText(name: "Photo record.jpg", data: data, utType: .image)
                app.addDocument(name: "Photo record", text: text)
            } catch {
                importError = message(for: error, name: "the photo")
            }
        }
    }

    private func message(for error: Error, name: String) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Amber couldn't read \(name)."
    }

    static let samplePanel = """
    THE DOCTORS LABORATORY - Routine Panel
    Patient: PUCHKOV, Kirill   DOB: 14/03/1992   Collected: 05/06/2026

    HbA1c                36 mmol/mol      (ref 20-41)
    Ferritin             18 ug/L          (ref 15-150)   LOW END
    Haemoglobin          128 g/L          (ref 120-150)

    Comment: No action required on this panel. Repeat ferritin in 3 months.
    """
}

extension View {
    func cardBackground() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.amberSoft.opacity(0.4)))
    }
}
