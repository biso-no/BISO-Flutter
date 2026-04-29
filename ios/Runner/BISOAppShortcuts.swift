import AppIntents
import Foundation

@available(iOS 16.0, *)
struct OpenBISOFeatureIntent: AppIntent {
  static var title: LocalizedStringResource = "Open BISO Feature"
  static var description = IntentDescription("Open a specific feature in BISO.")
  private static let appGroupIdentifier = "group.com.biso.no"
  private static let pendingDeepLinkKey = "pendingDeepLink"

  @Parameter(title: "Feature")
  var feature: BISOFeature

  init() {
    self.feature = .newReimbursement
  }

  init(feature: BISOFeature) {
    self.feature = feature
  }

  static var openAppWhenRun: Bool { true }

  func perform() async throws -> some IntentResult {
    let url = URL(string: "https://biso.no/app/\(feature.path)")!
    UserDefaults(suiteName: Self.appGroupIdentifier)?
      .set(url.absoluteString, forKey: Self.pendingDeepLinkKey)
    return .result()
  }
}

@available(iOS 16.0, *)
enum BISOFeature: String, AppEnum {
  case newReimbursement
  case events
  case marketplace
  case jobs
  case profile
  case aiAssistant

  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "BISO Feature")

  static var caseDisplayRepresentations: [BISOFeature: DisplayRepresentation] = [
    .newReimbursement: "New reimbursement",
    .events: "Events",
    .marketplace: "Marketplace",
    .jobs: "Jobs",
    .profile: "Profile",
    .aiAssistant: "AI assistant",
  ]

  var path: String {
    switch self {
    case .newReimbursement:
      return "expenses/new"
    case .events:
      return "events"
    case .marketplace:
      return "marketplace"
    case .jobs:
      return "jobs"
    case .profile:
      return "profile"
    case .aiAssistant:
      return "ai-chat"
    }
  }
}

@available(iOS 16.0, *)
struct BISOAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenBISOFeatureIntent(feature: BISOFeature.newReimbursement),
      phrases: [
        "New reimbursement in \(.applicationName)",
        "Submit expense in \(.applicationName)",
        "Open expenses in \(.applicationName)",
      ],
      shortTitle: "New reimbursement",
      systemImageName: "receipt"
    )
    AppShortcut(
      intent: OpenBISOFeatureIntent(feature: BISOFeature.events),
      phrases: [
        "Open events in \(.applicationName)",
        "Show BISO events in \(.applicationName)",
      ],
      shortTitle: "Events",
      systemImageName: "calendar"
    )
    AppShortcut(
      intent: OpenBISOFeatureIntent(feature: BISOFeature.marketplace),
      phrases: [
        "Open marketplace in \(.applicationName)",
        "Open BISO shop in \(.applicationName)",
      ],
      shortTitle: "Marketplace",
      systemImageName: "bag"
    )
    AppShortcut(
      intent: OpenBISOFeatureIntent(feature: BISOFeature.jobs),
      phrases: [
        "Open jobs in \(.applicationName)",
        "Open volunteer jobs in \(.applicationName)",
      ],
      shortTitle: "Jobs",
      systemImageName: "briefcase"
    )
    AppShortcut(
      intent: OpenBISOFeatureIntent(feature: BISOFeature.profile),
      phrases: [
        "Open profile in \(.applicationName)",
        "Show my BISO profile in \(.applicationName)",
      ],
      shortTitle: "Profile",
      systemImageName: "person.crop.circle"
    )
    AppShortcut(
      intent: OpenBISOFeatureIntent(feature: BISOFeature.aiAssistant),
      phrases: [
        "Open AI assistant in \(.applicationName)",
        "Open BISO assistant in \(.applicationName)",
      ],
      shortTitle: "AI assistant",
      systemImageName: "sparkles"
    )
  }
}
