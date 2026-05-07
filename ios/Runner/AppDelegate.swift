import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let appGroupIdentifier = "group.com.biso.no"
  private let expenseIntakeChannelName = "biso/expense_intake"
  private let pendingDeepLinkKey = "pendingDeepLink"
  private var expenseIntakeChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: expenseIntakeChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      expenseIntakeChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        if call.method == "takePendingExpenseIntakeBatches" {
          result(self?.drainSharedExpenseBatches() ?? [])
          return
        }
        if call.method == "takePendingShortcutDeepLink" {
          result(self?.takePendingShortcutDeepLink())
          return
        }
        result(FlutterMethodNotImplemented)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    expenseIntakeChannel?.invokeMethod("nativeEntrypointReceived", arguments: nil)
  }

  private func drainSharedExpenseBatches() -> [[String: Any]] {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      return []
    }

    let batchesDirectory = container
      .appendingPathComponent("ExpenseIntake", isDirectory: true)
      .appendingPathComponent("batches", isDirectory: true)
    guard let batchDirectories = try? FileManager.default.contentsOfDirectory(
      at: batchesDirectory,
      includingPropertiesForKeys: nil
    ) else {
      return []
    }

    var batches: [[String: Any]] = []
    for directory in batchDirectories {
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue else {
        continue
      }
      let manifest = directory.appendingPathComponent("batch.json")
      guard let data = try? Data(contentsOf: manifest),
            let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        continue
      }
      batches.append(decoded)
      try? FileManager.default.removeItem(at: manifest)
    }
    return batches
  }

  private func takePendingShortcutDeepLink() -> String? {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
          let value = defaults.string(forKey: pendingDeepLinkKey),
          !value.isEmpty else {
      return nil
    }
    defaults.removeObject(forKey: pendingDeepLinkKey)
    return value
  }
}
