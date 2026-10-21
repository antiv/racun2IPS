import Flutter
import PDFKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Kanal deli ime sa Androidom: deljenje intentom (getSharedPayload) na iOS-u
    // vraća nil, a renderPdfPages renderuje PDF preko PDFKit-a.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Invoice2IpsShared") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "rs.antonijevic.invoice2ips/shared",
      binaryMessenger: registrar.messenger()
    )

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getSharedImage", "getSharedPayload":
        result(nil)
      case "renderPdfPages":
        guard
          let args = call.arguments as? [String: Any],
          let typedData = args["bytes"] as? FlutterStandardTypedData
        else {
          result([FlutterStandardTypedData]())
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          let pages = Self.renderPdfDataToPngPages(typedData.data)
          DispatchQueue.main.async {
            result(pages)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Renderuje stranice PDF dokumenta u PNG slike visoke rezolucije (~2000px po dužoj strani)
  /// pomoću ugrađenog iOS PDFKit-a.
  private static func renderPdfDataToPngPages(_ data: Data) -> [FlutterStandardTypedData] {
    guard let document = PDFDocument(data: data), document.pageCount > 0 else {
      return []
    }
    let count = document.pageCount
    let indices: [Int] = count <= 3 ? Array(0..<count) : [0, 1, count - 1]
    var output: [FlutterStandardTypedData] = []

    for index in indices {
      guard let page = document.page(at: index) else { continue }
      let bounds = page.bounds(for: .mediaBox)
      let maxDim = max(bounds.width, bounds.height, 1.0)
      let scale = min(max(2000.0 / maxDim, 2.0), 4.0)
      let targetSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

      let format = UIGraphicsImageRendererFormat()
      format.scale = 1.0
      format.opaque = true
      let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

      let image = renderer.image { ctx in
        UIColor.white.setFill()
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        let cgContext = ctx.cgContext
        cgContext.saveGState()
        cgContext.translateBy(x: 0, y: targetSize.height)
        cgContext.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: cgContext)
        cgContext.restoreGState()
      }

      if let pngData = image.pngData() {
        output.append(FlutterStandardTypedData(bytes: pngData))
      }
    }

    return output
  }
}
