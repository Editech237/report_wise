import Foundation
import PDFKit
import ImageIO

// Compile alongside macos/Runner/LocalStudentOCR.swift; emits word boxes as JSON.
do {
  if CommandLine.arguments.count > 3 {
    let doc = CGPDFDocument(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL)!
    let page = doc.page(at: 1)!
    let bounds = page.getBoxRect(.cropBox)
    let scale = min(3.5, 3200 / max(bounds.width, bounds.height))
    let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect)
    context.scaleBy(x: scale, y: scale)
    context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: bounds.size), rotate: 0, preserveAspectRatio: true))
    context.drawPDFPage(page)
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[3]) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, context.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
  }
  let pages = try LocalStudentOCR.extract(path: CommandLine.arguments[1]) { page, total in
    FileHandle.standardError.write(Data("Page \(page)/\(total)\n".utf8))
  }
  let data = try JSONSerialization.data(withJSONObject: pages, options: [.prettyPrinted, .sortedKeys])
  try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
} catch {
  FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
  exit(1)
}
