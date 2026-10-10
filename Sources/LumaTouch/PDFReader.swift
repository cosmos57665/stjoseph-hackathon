import AppKit
import PDFKit
import Vision

struct LessonPage: Identifiable {
    var id: Int
    var source: String
    var extraction: String
    var transcript: String? = nil
    var simplified: String? = nil
    var text: String { transcript ?? source }
}

enum PDFReader {
    static func open(_ url: URL, progress: @escaping (Int, Int) -> Void) throws -> [LessonPage] {
        guard let document = PDFDocument(url: url) else { throw AppError.message("This file could not be opened as a PDF.") }
        guard !document.isLocked else { throw AppError.message("This PDF is password-protected. Unlock it before importing.") }
        guard document.pageCount > 0 else { throw AppError.message("The PDF has no pages.") }
        guard document.pageCount <= 300 else { throw AppError.message("For this prototype, import a PDF with 300 pages or fewer.") }
        var pages: [LessonPage] = []
        for i in 0..<document.pageCount {
            progress(i + 1, document.pageCount)
            guard let page = document.page(at: i) else { throw AppError.message("Could not read page \(i + 1).") }
            let embedded = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if embedded.count >= 12 {
                pages.append(LessonPage(id: i, source: embedded, extraction: "PDF text"))
            } else {
                let image = try render(page)
                let text = recognize(image)
                pages.append(LessonPage(id: i, source: text.isEmpty ? embedded : text,
                                        extraction: text.isEmpty ? "Needs AI transcription" : "On-device OCR"))
            }
        }
        return pages
    }

    private final class RecognitionResult: @unchecked Sendable {
        private let lock = NSLock()
        private var text = ""
        func set(_ text: String) { lock.lock(); self.text = text; lock.unlock() }
        func get() -> String { lock.lock(); defer { lock.unlock() }; return text }
    }

    static func recognize(_ image: CGImage) -> String {
        let result = RecognitionResult()
        let finished = DispatchSemaphore(value: 0)
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        // Bound OS recognition work. A missing language asset must not stop PDF
        // import; the original page can still be sent to a vision provider.
        DispatchQueue.global(qos: .userInitiated).async {
            defer { finished.signal() }
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
                result.set((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"))
            } catch { /* Mark the page for explicit AI transcription. */ }
        }
        if finished.wait(timeout: .now() + 8) == .timedOut { request.cancel(); return "" }
        return result.get()
    }

    static func render(_ page: PDFPage) throws -> CGImage {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { throw AppError.message("Invalid page dimensions.") }
        let scale = min(2.5, 1800 / max(bounds.width, bounds.height))
        let width = max(1, Int(bounds.width * scale)), height = max(1, Int(bounds.height * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw AppError.message("Could not render this page.")
        }
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { throw AppError.message("Could not render this page.") }
        return image
    }

    static func imageData(url: URL, page index: Int) throws -> Data {
        guard let document = PDFDocument(url: url), let page = document.page(at: index) else { throw AppError.message("The PDF is no longer available. Import it again.") }
        return try withExtendedLifetime(document) {
            let bitmap = NSBitmapImageRep(cgImage: try render(page))
            guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
                throw AppError.message("Could not prepare the page image.")
            }
            return data
        }
    }
}
