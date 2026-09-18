import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let appGroupIdentifier = "group.com.biso.no"
  private let statusLabel = UILabel()
  private let addButton = UIButton(type: .system)
  private let cancelButton = UIButton(type: .system)

  /// The only types the reimbursement API accepts, and so the only ones
  /// this extension may promise to take. Advertising more — HEIC, WebP, or
  /// `public.image` as a catch-all — got the file copied in and then
  /// dropped by the app, after the student had already been told the
  /// receipt was added.
  private static let acceptedTypes: [UTType] = [.pdf, .jpeg, .png]

  private static let acceptedTypesMessage =
    "BISO Expenses takes PDF, PNG and JPEG receipts. Add a photo in another "
      + "format from inside the BISO app — it converts it for you."

  override func viewDidLoad() {
    super.viewDidLoad()
    configureView()
  }

  private func configureView() {
    view.backgroundColor = .systemBackground

    statusLabel.text = "Add PDF, PNG or JPEG receipts to BISO Expenses."
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0
    statusLabel.font = .preferredFont(forTextStyle: .headline)

    addButton.setTitle("Add to BISO Expenses", for: .normal)
    addButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    addButton.addTarget(self, action: #selector(addToBISO), for: .touchUpInside)

    cancelButton.setTitle("Cancel", for: .normal)
    cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

    let stack = UIStackView(arrangedSubviews: [statusLabel, addButton, cancelButton])
    stack.axis = .vertical
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  @objc private func addToBISO() {
    addButton.isEnabled = false
    statusLabel.text = "Importing receipts..."
    Task {
      do {
        let result = try await importAttachments()
        await MainActor.run {
          statusLabel.text = Self.addedMessage(
            imported: result.imported,
            skipped: result.skipped
          )
          // Long enough to read when something was left behind.
          completeAfterDelay(seconds: result.skipped == 0 ? 0.8 : 4)
        }
      } catch {
        await MainActor.run {
          statusLabel.text = error.localizedDescription
          addButton.isEnabled = true
        }
      }
    }
  }

  @objc private func cancel() {
    extensionContext?.cancelRequest(withError: NSError(
      domain: "BISOShareExtension",
      code: NSUserCancelledError,
      userInfo: nil
    ))
  }

  /// The message shown once the import is done. A file that was left out
  /// is said out loud: a receipt that disappears between the share sheet
  /// and the app is the one failure a student cannot do anything about.
  private static func addedMessage(imported: Int, skipped: Int) -> String {
    let added = imported == 1
      ? "Receipt added."
      : "\(imported) receipts added."
    if skipped == 0 {
      return "\(added) Open BISO to continue."
    }
    let left = skipped == 1
      ? "1 file could not be added."
      : "\(skipped) files could not be added."
    return "\(added) \(left) \(acceptedTypesMessage)"
  }

  private func importAttachments() async throws -> (imported: Int, skipped: Int) {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      throw ShareImportError("BISO could not access its shared receipt inbox.")
    }

    let batchId = "ios_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString)"
    let batchDirectory = container
      .appendingPathComponent("ExpenseIntake", isDirectory: true)
      .appendingPathComponent("batches", isDirectory: true)
      .appendingPathComponent(batchId, isDirectory: true)
    try FileManager.default.createDirectory(
      at: batchDirectory,
      withIntermediateDirectories: true
    )

    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
    var files: [[String: Any]] = []

    var skipped = 0
    for provider in providers {
      if let imported = try await importProvider(provider, into: batchDirectory) {
        files.append(imported)
      } else {
        skipped += 1
      }
    }

    guard !files.isEmpty else {
      try? FileManager.default.removeItem(at: batchDirectory)
      throw ShareImportError("Nothing here could be added. \(Self.acceptedTypesMessage)")
    }

    let manifest: [String: Any] = [
      "batchId": batchId,
      "source": "ios-share-extension",
      "createdAt": ISO8601DateFormatter().string(from: Date()),
      "files": files,
    ]
    let data = try JSONSerialization.data(withJSONObject: manifest)
    try data.write(to: batchDirectory.appendingPathComponent("batch.json"))
    return (files.count, skipped)
  }

  private func importProvider(
    _ provider: NSItemProvider,
    into directory: URL
  ) async throws -> [String: Any]? {
    guard let type = supportedType(for: provider) else { return nil }
    return try await withCheckedThrowingContinuation { continuation in
      provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let url else {
          continuation.resume(returning: nil)
          return
        }

        do {
          let fileName = self.uniqueFileName(
            in: directory,
            requested: self.safeFileName(url.lastPathComponent, type: type)
          )
          let destination = directory.appendingPathComponent(fileName)
          if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
          }
          try FileManager.default.copyItem(at: url, to: destination)
          let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
          continuation.resume(returning: [
            "fileName": fileName,
            "filePath": destination.path,
            "mimeType": type.preferredMIMEType ?? "application/octet-stream",
            "sizeBytes": attributes[.size] as? Int64 ?? 0,
          ])
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// The first type this provider offers that the app can actually take.
  ///
  /// A HEIC photo shared from Photos registers `public.jpeg` alongside
  /// `public.heic`, so this still finds a JPEG for it and iOS does the
  /// conversion while loading. A file that is only ever HEIC — say, from
  /// Files — has nothing here and is refused with a reason.
  private func supportedType(for provider: NSItemProvider) -> UTType? {
    for identifier in provider.registeredTypeIdentifiers {
      guard let type = UTType(identifier) else { continue }
      if Self.acceptedTypes.contains(where: { type.conforms(to: $0) }) {
        return type
      }
    }
    return nil
  }

  /// The extensions the app accepts for a type, preferred one first — the
  /// same list as `ExpenseIntakeService.supportedExtensions`. iOS knows more
  /// spellings (a JPEG may arrive as `.jpe` or `.jfif`), but the app decides
  /// by extension, so any other spelling is renamed to the preferred one.
  private static func acceptedExtensions(for type: UTType) -> [String] {
    if type.conforms(to: .jpeg) { return ["jpg", "jpeg"] }
    if type.conforms(to: .png) { return ["png"] }
    if type.conforms(to: .pdf) { return ["pdf"] }
    return []
  }

  private func safeFileName(_ original: String, type: UTType) -> String {
    let accepted = Self.acceptedExtensions(for: type)
    let fallbackExtension = accepted.first ?? type.preferredFilenameExtension ?? "dat"
    let cleaned = original
      .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
      .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
    // Plain string path handling: `URL(fileURLWithPath:)` would resolve a
    // bare name against the working directory, so "" or ".." would take
    // that directory's name instead of falling back to "receipt".
    let name = cleaned as NSString
    let base = name.deletingPathExtension
    if base.isEmpty || base == "." || base == ".." {
      return "receipt.\(fallbackExtension)"
    }
    // The name travels with the file and the app decides what it accepts by
    // extension, so a HEIC photo that iOS handed over as JPEG must stop
    // calling itself .heic, and a JPEG named .jpe must become .jpg —
    // otherwise the app refuses a file this extension has already said it
    // added.
    if accepted.contains(name.pathExtension.lowercased()) {
      return cleaned
    }
    return "\(base).\(fallbackExtension)"
  }

  private func uniqueFileName(in directory: URL, requested: String) -> String {
    let url = URL(fileURLWithPath: requested)
    let base = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
    var candidate = requested
    var index = 1
    while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
      candidate = "\(base)_\(index)\(ext)"
      index += 1
    }
    return candidate
  }

  private func completeAfterDelay(seconds: Double = 0.8) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
      self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
  }
}

struct ShareImportError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
