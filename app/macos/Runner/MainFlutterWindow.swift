import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var ocrChannel: FlutterMethodChannel?
  private let ocrQueue = DispatchQueue(label: "cm.reportwise.student-ocr", qos: .userInitiated)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(name: "reportwise/local_student_ocr",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    ocrChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "extractPdf" else { result(FlutterMethodNotImplemented); return }
      guard let arguments = call.arguments as? [String: Any], let path = arguments["path"] as? String else {
        result(FlutterError(code: "INVALID_PDF", message: "Choose a PDF first.", details: nil)); return
      }
      self?.ocrQueue.async {
        do {
          let pages = try LocalStudentOCR.extract(path: path) { page, total in
            DispatchQueue.main.async { channel.invokeMethod("progress", arguments: ["page": page, "total": total]) }
          }
          DispatchQueue.main.async { result(pages) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "OCR_FAILED", message: error.localizedDescription, details: nil)) }
        }
      }
    }

    super.awakeFromNib()
  }
}
