import Foundation
import PDFKit
import Vision

/// Extracts text from PDF files using PDFKit, with Vision OCR fallback for scanned docs.
enum PDFExtractor {

    static func extractText(from url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }

        // Try PDFKit text extraction first (fast, works for text-based PDFs)
        var pages: [String] = []
        for i in 0..<min(document.pageCount, 50) { // Cap at 50 pages
            if let page = document.page(at: i), let text = page.string, !text.isEmpty {
                pages.append(text)
            }
        }

        let pdfKitText = pages.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)

        if !pdfKitText.isEmpty {
            return pdfKitText
        }

        // Fallback: Vision OCR for scanned PDFs (first 10 pages only — slow)
        var ocrPages: [String] = []
        for i in 0..<min(document.pageCount, 10) {
            guard let page = document.page(at: i) else { continue }
            let pageRect = page.bounds(for: .mediaBox)
            guard let cgImage = page.thumbnail(of: CGSize(width: pageRect.width * 2, height: pageRect.height * 2), for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
                if let observations = request.results {
                    let pageText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    if !pageText.isEmpty {
                        ocrPages.append(pageText)
                    }
                }
            } catch {
                continue
            }
        }

        let ocrText = ocrPages.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return ocrText.isEmpty ? nil : ocrText
    }
}
