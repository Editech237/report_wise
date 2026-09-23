import Foundation
import PDFKit
import Vision

/// No network or model download: PDF rendering and OCR stay on this Mac.
enum LocalStudentOCR {
  static func extract(path: String, progress: (Int, Int) -> Void) throws -> [[String: Any]] {
    guard #available(macOS 11.0, *) else {
      throw failure("Free scanning requires macOS 11 or later.")
    }
    let url = URL(fileURLWithPath: path)
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let document = CGPDFDocument(url as CFURL), !document.isEncrypted else {
      throw failure("This PDF cannot be opened. Use an unlocked, valid PDF.")
    }
    guard (1...50).contains(document.numberOfPages) else {
      throw failure("Please split the register into PDFs of 1–50 pages.")
    }
    var pages = [[String: Any]]()
    for number in 1...document.numberOfPages {
      progress(number, document.numberOfPages)
      let payload: [String: Any] = try autoreleasepool {
        guard let page = document.page(at: number) else {
          throw failure("Could not open page \(number).")
        }
        let bounds = page.getBoxRect(.cropBox)
        guard bounds.width > 0, bounds.height > 0 else {
          throw failure("Page \(number) has invalid dimensions.")
        }
        let rotated = abs(page.rotationAngle) % 180 == 90
        let size = rotated ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        let scale = min(3.5, 3200 / max(size.width, size.height))
        let width = max(1, Int(size.width * scale))
        let height = max(1, Int(size.height * scale))
        guard let context = CGContext(data: nil, width: width, height: height,
          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
          throw failure("Could not render page \(number).")
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        // CGPDFPage's fitting transform does not enlarge small pages.
        context.scaleBy(x: scale, y: scale)
        context.concatenate(page.getDrawingTransform(.cropBox,
          rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw failure("Could not render page \(number).") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Revision 2 retains small isolated cells better in register scans.
        request.revision = VNRecognizeTextRequestRevision2
        request.minimumTextHeight = 0.003
        request.recognitionLanguages = ["en-US", "fr-FR"]
        // Preserve names and identifiers instead of dictionary-correcting them.
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        var words = [[String: Any]]()
        var lines = [String]()
        let regex = try NSRegularExpression(pattern: "\\S+")
        for observation in request.results ?? [] {
          guard let candidate = observation.topCandidates(1).first else { continue }
          lines.append(candidate.string)
          for match in regex.matches(in: candidate.string, range: NSRange(candidate.string.startIndex..., in: candidate.string)) {
            guard let range = Range(match.range, in: candidate.string),
              let box = try candidate.boundingBox(for: range)?.boundingBox else { continue }
            words.append([
              "text": String(candidate.string[range]), "confidence": Double(candidate.confidence),
              "x": Double(box.minX), "y": Double(1 - box.maxY),
              "width": Double(box.width), "height": Double(box.height),
            ])
          }
        }
        return ["page_number": number, "raw_text": lines.joined(separator: "\n"), "words": words]
      }
      pages.append(payload)
    }
    return pages
  }

  private static func failure(_ message: String) -> NSError {
    NSError(domain: "ReportWiseOCR", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
