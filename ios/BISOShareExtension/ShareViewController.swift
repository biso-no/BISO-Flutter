import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let appGroupIdentifier = "group.com.biso.no"
  private let statusLabel = UILabel()
  private let addButton = UIButton(type: .system)
  private let cancelButton = UIButton(type: .system)

  override func viewDidLoad() {
    super.viewDidLoad()
    configureView()
  }

  private func configureView() {
    view.backgroundColor = .systemBackground

    statusLabel.text = "Add selected receipts to BISO."
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0
    statusLabel.font = .preferredFont(forTextStyle: .headline)

    addButton.setTitle("Add to BISO", for: .normal)
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
        let count = try await importAttachments()
        await MainActor.run {
          statusLabel.text = count == 1
            ? "Receipt added. Open BISO to continue."
            : "\(count) receipts added. Open BISO to continue."
          completeAfterDelay()
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

  private func importAttachments() async throws -> Int {
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

    for provider in providers {
      if let imported = try await importProvider(provider, into: batchDirectory) {
        files.append(imported)
      }
    }

    guard !files.isEmpty else {
      try? FileManager.default.removeItem(at: batchDirectory)
      throw ShareImportError("No supported receipt files were selected.")
    }

    let manifest: [String: Any] = [
      "batchId": batchId,
      "source": "ios-share-extension",
      "createdAt": ISO8601DateFormatter().string(from: Date()),
      "files": files,
    ]
    let data = try JSONSerialization.data(withJSONObject: manifest)
    try data.write(to: batchDirectory.appendingPathComponent("batch.json"))
    return files.count
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

  private func supportedType(for provider: NSItemProvider) -> UTType? {
    let supported: [UTType] = [
      .pdf,
      .jpeg,
      .png,
      .webP,
      .heic,
      .heif,
      .image,
    ]
    for identifier in provider.registeredTypeIdentifiers {
      guard let type = UTType(identifier) else { continue }
      if supported.contains(where: { type.conforms(to: $0) }) {
        return type
      }
    }
    return nil
  }

  private func safeFileName(_ original: String, type: UTType) -> String {
    let fallbackExtension = type.preferredFilenameExtension ?? "dat"
    let fallback = "receipt.\(fallbackExtension)"
    let cleaned = original
      .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
      .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
    if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
      return fallback
    }
    if cleaned.contains(".") {
      return cleaned
    }
    return "\(cleaned).\(fallbackExtension)"
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

  private func completeAfterDelay() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
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
