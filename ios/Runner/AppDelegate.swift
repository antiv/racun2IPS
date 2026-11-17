import Flutter
import ImageIO
import PDFKit
import UIKit
import Vision

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

    // Kanal deli ime sa Androidom: getSharedPayload čita sadržaj koji je Share
    // Extension ostavio u App Group kontejneru, a renderPdfPages renderuje PDF
    // preko PDFKit-a.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Invoice2IpsShared") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "rs.antonijevic.invoice2ips/shared",
      binaryMessenger: registrar.messenger()
    )

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getSharedImage":
        result(nil)
      case "getSharedPayload":
        result(Self.takeSharedPayload())
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
      case "extractPdfText":
        guard
          let args = call.arguments as? [String: Any],
          let typedData = args["bytes"] as? FlutterStandardTypedData
        else {
          result([String]())
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          let texts = Self.extractPdfText(typedData.data)
          DispatchQueue.main.async {
            result(texts)
          }
        }
      case "recognizeTextNative":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          !path.isEmpty
        else {
          result(nil)
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          let ocrResult = Self.recognizeTextWithVision(filePath: path)
          DispatchQueue.main.async {
            result(ocrResult)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Preuzima (i briše) sadržaj koji je ShareExtension upisao u App Group
  /// kontejner, u istom obliku kao Android: {type, bytes | text}.
  private static func takeSharedPayload() -> [String: Any]? {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.rs.antonijevic.invoice2ips"
    ) else {
      return nil
    }
    let metaURL = container.appendingPathComponent("shared_payload.json")
    let payloadURL = container.appendingPathComponent("shared_payload.bin")
    guard
      let metaData = try? Data(contentsOf: metaURL),
      let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
      let type = meta["type"] as? String
    else {
      return nil
    }
    defer {
      try? FileManager.default.removeItem(at: metaURL)
      try? FileManager.default.removeItem(at: payloadURL)
    }
    var payload: [String: Any] = ["type": type]
    if let text = meta["text"] as? String {
      payload["text"] = text
    } else if let bytes = try? Data(contentsOf: payloadURL) {
      payload["bytes"] = FlutterStandardTypedData(bytes: bytes)
    } else {
      return nil
    }
    return payload
  }

  /// Čita tekstualni sloj PDF-a za iste stranice koje se renderuju (sve do 3,
  /// inače 1, 2. i poslednju). Skenirani PDF bez teksta vraća prazne stringove.
  private static func extractPdfText(_ data: Data) -> [String] {
    guard let document = PDFDocument(data: data), document.pageCount > 0 else {
      return []
    }
    let count = document.pageCount
    let indices: [Int] = count <= 3 ? Array(0..<count) : [0, 1, count - 1]
    return indices.map { document.page(at: $0)?.string ?? "" }
  }

  /// Renderuje stranice PDF dokumenta u PNG slike visoke rezolucije (~3000px po dužoj strani,
  /// da i sitan IPS QR kod na strani ima dovoljno piksela po modulu za ML Kit)
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
      let scale = min(max(3000.0 / maxDim, 2.0), 4.0)
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

  /// Izvršava lokalni OCR pomoću ugrađenog Apple Vision okvira (`VNRecognizeTextRequest`),
  /// koji nativno čita i ćirilicu i latinicu na uređaju, i vraća pun tekst i listu linija
  /// sa koordinatama u pikselima.
  private static func recognizeTextWithVision(filePath: String) -> [String: Any]? {
    guard
      let uiImage = UIImage(contentsOfFile: filePath),
      let cgImage = uiImage.cgImage
    else {
      return nil
    }

    let width = Double(uiImage.size.width * uiImage.scale)
    let height = Double(uiImage.size.height * uiImage.scale)
    let orientation = cgOrientation(from: uiImage.imageOrientation)

    var fullLines: [String] = []
    var lines: [[String: Any]] = []

    let request = VNRecognizeTextRequest { req, _ in
      guard let observations = req.results as? [VNRecognizedTextObservation] else {
        return
      }
      for obs in observations {
        guard let topCandidate = obs.topCandidates(1).first else { continue }
        let rawString = topCandidate.string
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }

        var tokenRanges: [Range<String.Index>] = []
        var tokenStart: String.Index? = nil
        for idx in rawString.indices {
          if rawString[idx].isWhitespace {
            if let start = tokenStart {
              tokenRanges.append(start..<idx)
              tokenStart = nil
            }
          } else if tokenStart == nil {
            tokenStart = idx
          }
        }
        if let start = tokenStart {
          tokenRanges.append(start..<rawString.endIndex)
        }

        var segWords: [String] = []
        var segLeft = 0.0
        var segTop = 0.0
        var segRight = 0.0
        var segBottom = 0.0
        var wordHeightSum = 0.0

        func flushSegment() {
          let segText = segWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
          if !segText.isEmpty {
            fullLines.append(segText)
            lines.append([
              "text": segText,
              "left": segLeft,
              "top": segTop,
              "right": segRight,
              "bottom": segBottom,
            ])
          }
          segWords.removeAll()
          wordHeightSum = 0.0
        }

        for range in tokenRanges {
          let wText = String(rawString[range])
          if wText.isEmpty || wText.allSatisfy({ "|¦[]_—~\\/".contains($0) }) {
            continue
          }
          let box = (try? topCandidate.boundingBox(for: range))?.boundingBox ?? obs.boundingBox
          let wLeft = Double(box.minX) * width
          let wRight = Double(box.maxX) * width
          let wTop = Double(1.0 - box.maxY) * height
          let wBottom = Double(1.0 - box.minY) * height
          let wWidth = max(1.0, wRight - wLeft)
          let wHeight = max(1.0, wBottom - wTop)

          if (wText == "I" || wText == "l" || wText == "1" || wText == "!") && wHeight > wWidth * 5.0 {
            continue
          }

          if segWords.isEmpty {
            segWords.append(wText)
            segLeft = wLeft
            segTop = wTop
            segRight = wRight
            segBottom = wBottom
            wordHeightSum = wHeight
          } else {
            let avgWordHeight = max(1.0, wordHeightSum / Double(segWords.count))
            let gap = wLeft - segRight
            if gap > max(avgWordHeight * 1.65, 18.0) {
              flushSegment()
              segWords.append(wText)
              segLeft = wLeft
              segTop = wTop
              segRight = wRight
              segBottom = wBottom
              wordHeightSum = wHeight
            } else {
              segWords.append(wText)
              segLeft = min(segLeft, wLeft)
              segTop = min(segTop, wTop)
              segRight = max(segRight, wRight)
              segBottom = max(segBottom, wBottom)
              wordHeightSum += wHeight
            }
          }
        }
        flushSegment()
      }
    }

    request.recognitionLevel = .accurate
    // Isključujemo rusku/ukrajinsku rečničku autokorekciju kako Apple Vision ne bi
    // menjao srpske nazive primalaca, gradova i svrhe uplate u ruske reči.
    request.usesLanguageCorrection = false
    if #available(iOS 16.0, *) {
      request.automaticallyDetectsLanguage = true
    }
    request.recognitionLanguages = ["sr-Cyrl", "sr-Latn", "ru-RU", "uk-UA", "en-US"]

    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
    do {
      try handler.perform([request])
      return [
        "text": fullLines.joined(separator: "\n"),
        "lines": lines,
      ]
    } catch {
      return nil
    }
  }

  private static func cgOrientation(
    from uiOrientation: UIImage.Orientation
  ) -> CGImagePropertyOrientation {
    switch uiOrientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}
