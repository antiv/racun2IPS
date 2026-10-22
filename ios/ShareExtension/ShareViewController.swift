import UIKit
import UniformTypeIdentifiers

/// Share Extension: prima PDF, sliku ili tekst računa iz iOS share sheet-a,
/// upisuje ih u zajednički App Group kontejner i otvara glavnu aplikaciju.
/// Glavna aplikacija sadržaj preuzima preko `getSharedPayload` (AppDelegate),
/// isto kao Android ACTION_SEND — i kad otvaranje ne uspe, preuzima ga pri
/// sledećem pokretanju.
class ShareViewController: UIViewController {
  static let appGroup = "group.rs.antonijevic.invoice2ips"
  static let payloadFile = "shared_payload.bin"
  static let metaFile = "shared_payload.json"

  private var handled = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !handled else { return }
    handled = true
    Task { await handleShare() }
  }

  private func handleShare() async {
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }

    var saved = false
    // Redosled: PDF, slika, tekst — PDF često nosi i sliku pregleda.
    if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }),
       let data = await loadData(provider, type: .pdf) {
      saved = save(type: "pdf", data: data, text: nil)
    } else if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }),
              let data = await loadData(provider, type: .image),
              let jpeg = Self.jpegData(from: data) {
      saved = save(type: "image", data: jpeg, text: nil)
    } else if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }),
              let text = await loadText(provider) {
      saved = save(type: "text", data: nil, text: text)
    }

    if saved {
      openMainApp()
    }
    extensionContext?.completeRequest(returningItems: nil)
  }

  private func loadData(_ provider: NSItemProvider, type: UTType) async -> Data? {
    await withCheckedContinuation { continuation in
      provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
        continuation.resume(returning: data)
      }
    }
  }

  private func loadText(_ provider: NSItemProvider) async -> String? {
    await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
        continuation.resume(returning: item as? String)
      }
    }
  }

  /// HEIC i ostali formati iz Photos-a se pretvaraju u JPEG, jer ga očekuju
  /// lokalni QR/OCR tok i Gemini (image/jpeg).
  private static func jpegData(from data: Data) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    return image.jpegData(compressionQuality: 0.92)
  }

  /// Upisuje sadržaj u App Group kontejner; metapodaci se pišu poslednji, kao
  /// oznaka da je sadržaj kompletan.
  private func save(type: String, data: Data?, text: String?) -> Bool {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: Self.appGroup
    ) else {
      return false
    }
    do {
      let payloadURL = container.appendingPathComponent(Self.payloadFile)
      if let data {
        try data.write(to: payloadURL, options: .atomic)
      } else {
        try? FileManager.default.removeItem(at: payloadURL)
      }
      var meta: [String: Any] = ["type": type]
      if let text { meta["text"] = text }
      let json = try JSONSerialization.data(withJSONObject: meta)
      try json.write(to: container.appendingPathComponent(Self.metaFile), options: .atomic)
      return true
    } catch {
      return false
    }
  }

  /// Extension nema UIApplication.shared, pa se aplikacija nalazi kroz
  /// responder lanac i otvara preko URL šeme `invoice2ips://`.
  private func openMainApp() {
    guard let url = URL(string: "invoice2ips://share") else { return }
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication {
        application.open(url, options: [:], completionHandler: nil)
        return
      }
      responder = current.next
    }
  }
}
