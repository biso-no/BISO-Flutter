import Flutter
import PassKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let appGroupIdentifier = "group.com.biso.no"
  private let expenseIntakeChannelName = "biso/expense_intake"
  private let pendingDeepLinkKey = "pendingDeepLink"
  private var expenseIntakeChannel: FlutterMethodChannel?
  private let walletChannelName = "biso/wallet"
  private var walletChannel: FlutterMethodChannel?
  private var pendingWalletResult: FlutterResult?
  private var pendingWalletPass: PKPass?
  /// The add sheet the pending result belongs to. Weak: a sheet UIKit never
  /// presented is released, which marks the pending result as stale.
  private weak var pendingWalletSheet: PKAddPassesViewController?
  private var walletRequest = 0

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

      let wallet = FlutterMethodChannel(
        name: walletChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      walletChannel = wallet
      wallet.setMethodCallHandler { [weak self] call, result in
        self?.handleWalletCall(call, result: result)
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

// MARK: - Apple Wallet

extension AppDelegate: PKAddPassesViewControllerDelegate {
  fileprivate func handleWalletCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "canAddPasses":
      result(PKAddPassesViewController.canAddPasses())
    case "addPass":
      if pendingWalletResult != nil {
        if let sheet = pendingWalletSheet, sheet.presentingViewController != nil {
          result(FlutterError(code: "busy", message: nil, details: nil))
          return
        }
        // The last sheet went away without its delegate call (or was never
        // shown): settle that call so it cannot block this one forever.
        finishWallet("cancelled")
      }
      guard
        let args = call.arguments as? [String: Any],
        let data = args["pass"] as? FlutterStandardTypedData,
        let pass = try? PKPass(data: data.data)
      else {
        result(FlutterError(code: "invalid_pass", message: nil, details: nil))
        return
      }
      guard let sheet = PKAddPassesViewController(pass: pass) else {
        result(FlutterError(code: "cannot_add", message: nil, details: nil))
        return
      }
      guard let presenter = topViewController() else {
        result(FlutterError(code: "no_presenter", message: nil, details: nil))
        return
      }
      sheet.delegate = self
      // Swiping the sheet away would skip the delegate call.
      sheet.isModalInPresentation = true
      walletRequest += 1
      let request = walletRequest
      pendingWalletResult = result
      pendingWalletPass = pass
      pendingWalletSheet = sheet
      presenter.present(sheet, animated: true) { [weak self, weak sheet] in
        guard let self, request == self.walletRequest, self.pendingWalletResult != nil else {
          return
        }
        // UIKit declines a presentation (e.g. mid-transition) without an
        // error; the sheet is then not on screen.
        if sheet?.presentingViewController == nil {
          self.finishWallet(FlutterError(code: "no_presenter", message: nil, details: nil))
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
    controller.dismiss(animated: true)
    // A sheet whose call was already settled must not answer a newer one.
    guard controller === pendingWalletSheet else { return }
    // containsPass only sees pass types listed in the app's entitlements.
    // Without that capability this reports "cancelled" and the Add button
    // simply stays visible.
    let added = pendingWalletPass.map { PKPassLibrary().containsPass($0) } ?? false
    finishWallet(added ? "added" : "cancelled")
  }

  /// Answers the pending `addPass` call, once, and clears its state.
  private func finishWallet(_ value: Any?) {
    let pending = pendingWalletResult
    pendingWalletResult = nil
    pendingWalletPass = nil
    pendingWalletSheet = nil
    pending?(value)
  }

  private func topViewController() -> UIViewController? {
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
