//
//  RecordImport.swift
//  AmberAI
//
//  Turning a real file into the plain text the Records reader expects. Everything here
//  is on-device: PDFKit pulls the text layer out of a lab PDF, and Vision OCRs a scan
//  or a phone photo of a paper letter. No network, no key — the same contract the rest
//  of the Records section keeps. We only produce text; parseDocument still does the
//  transcribing, and it still never interprets.
//
//  Formats: the records people actually hold. eMed, GP surgeries and private labs (The
//  Doctors Laboratory, Randox, etc.) hand out PDFs — blood panels, clinic letters,
//  prescriptions. Everything else tends to be a photo of a paper letter, or pasted text.
//

import Foundation
import PDFKit
import Vision
import UniformTypeIdentifiers
import ImageIO
import UIKit

enum RecordImportError: LocalizedError {
    case unreadable
    case noText(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: return "Amber couldn't open that file."
        case .noText(let msg): return msg
        }
    }
}

/// Extracts plain text from an imported record. Pure input handling — it does not
/// classify or interpret; it hands the text straight to `parseDocument`.
enum RecordReader {

    /// The formats the file importer offers. PDF and photos cover almost every real
    /// record; plain text and CSV cover a pasted-into-a-file panel.
    static let importableTypes: [UTType] = [.pdf, .image, .plainText, .commaSeparatedText, .rtf, .text]

    static func extractText(name: String, data: Data, utType: UTType?) async throws -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        let isPDF = (utType?.conforms(to: .pdf) ?? false) || ext == "pdf"
        let isImage = (utType?.conforms(to: .image) ?? false)
            || ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp"].contains(ext)
        let isText = (utType?.conforms(to: .text) ?? false)
            || ["txt", "text", "md", "csv", "tsv", "log", "rtf"].contains(ext)

        if isPDF { return try await readPDF(data) }
        if isImage { return try await ocrImageData(data) }
        if isText { return readText(data, ext: ext) }

        // Unknown extension: give text a chance before giving up (some PDFs and text
        // files arrive with no usable type), otherwise report it cleanly.
        if let doc = PDFDocument(data: data) {
            return try await readPDF(data, existing: doc)
        }
        let guess = readText(data, ext: ext)
        if !guess.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return guess }
        throw RecordImportError.noText("Amber doesn't recognise that file type. A PDF, a photo, or pasted text works best.")
    }

    // MARK: - PDF

    private static func readPDF(_ data: Data, existing: PDFDocument? = nil) async throws -> String {
        guard let doc = existing ?? PDFDocument(data: data) else { throw RecordImportError.unreadable }

        // A born-digital lab PDF has a real text layer — read it directly and exactly.
        let embedded = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if embedded.count >= 20 { return doc.string ?? embedded }

        // A scanned PDF is really an image. Render each page and OCR it.
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2   // upscale so small print survives OCR
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = page.thumbnail(of: size, for: .mediaBox)
            if let cg = image.cgImage {
                let text = try await ocrCGImage(cg)
                if !text.isEmpty { pages.append(text) }
            }
        }
        let ocr = pages.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !ocr.isEmpty { return ocr }
        if !embedded.isEmpty { return embedded }
        throw RecordImportError.noText("This PDF has no readable text. If it's a scan, a clear, flat photo often reads better.")
    }

    // MARK: - Images

    private static func ocrImageData(_ data: Data) async throws -> String {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw RecordImportError.unreadable
        }
        let text = try await ocrCGImage(cg)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RecordImportError.noText("Amber couldn't find any text in that image. A flat, well-lit photo reads best.")
        }
        return text
    }

    /// On-device OCR. `.accurate` with language correction, because a lab panel is
    /// dense small print where speed matters less than reading "18 ug/L" correctly.
    private static func ocrCGImage(_ cg: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { req, err in
                    if let err { cont.resume(throwing: err); return }
                    let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                    let lines = obs.compactMap { $0.topCandidates(1).first?.string }
                    cont.resume(returning: lines.joined(separator: "\n"))
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                do { try handler.perform([request]) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    // MARK: - Text

    private static func readText(_ data: Data, ext: String) -> String {
        if ext == "rtf",
           let attr = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil) {
            return attr.string
        }
        return String(decoding: data, as: UTF8.self)
    }
}
