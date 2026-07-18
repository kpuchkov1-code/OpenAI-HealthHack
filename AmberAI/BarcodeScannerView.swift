//
//  BarcodeScannerView.swift
//  AmberAI
//
//  A thin SwiftUI wrapper over VisionKit's live barcode scanner. It calls `onScan` once
//  with the first barcode it recognises. VisionKit needs a real camera, so `isSupported`
//  lets the UI offer a graceful fallback (search / describe) on the simulator.
//

import SwiftUI
import VisionKit

struct BarcodeScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    /// True only where a live scanner can actually run (device with a camera).
    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning()
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var fired = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            guard !fired else { return }
            for case let .barcode(barcode) in items {
                if let payload = barcode.payloadStringValue, !payload.isEmpty {
                    fired = true
                    onScan(payload)
                    return
                }
            }
        }
    }
}
