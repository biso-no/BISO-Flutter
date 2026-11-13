# BISO Flutter App

## Overview

BISO is the mobile app for BI Student Organisation. The app is built in Flutter and gives students a campus-aware entry point for events, volunteer work, marketplace listings, memberships, expenses, student ID, profile management, notifications, and BISO information.

The app currently uses Appwrite as the primary backend. Some content is still fetched from the existing BISO WordPress/API stack while the newer Next.js and Appwrite-backed systems are being moved fully into production.

## Features

- **Authentication and onboarding**: Appwrite email OTP login, user profile lookup, onboarding, campus selection, and BI/BISO email-domain restrictions.
- **Home**: campus-aware home screen with events, marketplace/webshop highlights, large event promotion, campus information, weather, and quick actions.
- **Explore**: events, public transport departures, marketplace, webshop products, organization units, expenses, volunteer/jobs, AI assistant, and campus detail pages.
- **Profile**: user profile, settings, student ID, payment information, privacy preferences, membership status, and authenticated-only flows.
- **Events and jobs**: fetched through WordPress/API-backed paths and Appwrite functions while Appwrite content migration continues.
- **Marketplace and webshop**: Appwrite-backed student marketplace plus webshop product data fetched through the BISO API.
- **Expenses**: expense creation, attachments, receipt parsing, summarization, and status tracking through Appwrite tables, storage, and functions.
- **Memberships**: membership plans and user membership lookup through Appwrite functions.
- **AI assistant**: streaming assistant UI backed by the public assistant API, with tool-aware rendering and SharePoint-oriented result components.
- **Notifications and deep links**: Firebase Cloud Messaging, local notifications, and app links/deep links.
- **Localization**: English and Norwegian locales.
- **Special modes**: large event detail routes and validator/controller mode.

## Architecture

The app follows a feature-oriented Flutter structure with Riverpod for state management and `go_router` for navigation.

- `lib/main.dart` initializes Firebase, notifications, deep links, localization, theming, Riverpod, and all app routes.
- `lib/core/` contains constants, theme, exceptions, logging, and shared utilities.
- `lib/data/models/` contains data models used by Appwrite, WordPress/API payloads, and UI features.
- `lib/data/services/` contains Appwrite, API, Firebase-related, and external API service clients.
- `lib/providers/` contains Riverpod providers for auth, campus, membership, notifications, locale, expenses, weather, and UI state.
- `lib/presentation/` contains screens and reusable widgets.
- `lib/schema/appwrite/` mirrors Appwrite table schemas as Dart classes.
- `lib/generated/l10n/` contains ARB files and generated localization code.

The main navigation tabs are Home, Explore, and Profile. Chat screens and services still exist, but the chat tab is currently disabled from the bottom navigation during launch.

## Backend and Data Sources

### Appwrite

Appwrite is the main backend for auth, tables, storage, realtime, functions, teams, and messaging. The global Appwrite client is configured in `lib/data/services/appwrite_service.dart`.

Current constants live in `lib/core/constants/app_constants.dart`:

- Endpoint: `https://appwrite.biso.no/v1`
- Project: `biso`
- Database: `app`
- API base: `https://api.biso.no`
- Public assistant endpoint: `/api/public-assistant`
- Storage buckets: `products`, `expenses`
- Appwrite functions include receipt parsing, expense summarization, events, jobs, and webshop sync.

Do not add secrets to source control. Appwrite endpoint IDs and public project/database IDs are currently committed because the app uses them at runtime, but private keys, signing files, service account JSON, and production credentials must stay out of the repo.

### WordPress and BISO API

Some features still depend on the existing WordPress/API stack:

- Events use WordPress/API-backed services and Appwrite functions.
- Jobs prefer an Appwrite function that fetches WordPress-backed data.
- Webshop products are fetched through the BISO API.

Use the service files in `lib/data/services/` as the source of truth for current runtime behavior.

### External APIs

- Firebase is used for Cloud Messaging and notification setup.
- MET Norway Locationforecast is used for weather.
- Entur-related data is used for campus departures/transit.
- The AI assistant calls the BISO public assistant API and streams responses to the Flutter client.

## Project Structure

```text
.
|-- android/                    # Android platform project
|-- ios/                        # iOS platform project and Fastlane config
|-- assets/                     # App logo, splash image, campus images
|-- lib/
|   |-- core/                   # Constants, theme, logging, utilities
|   |-- data/                   # Models and services
|   |-- generated/l10n/         # ARB files and generated localizations
|   |-- presentation/           # Screens and widgets
|   |-- providers/              # Riverpod providers
|   |-- schema/appwrite/        # Appwrite table schema classes
|   |-- firebase_options.dart   # Generated Firebase options
|   `-- main.dart               # App entry point and router
|-- scripts/                    # Maintenance scripts
|-- .github/workflows/          # CI checks and store releases
|-- appwrite.config.json        # Appwrite project/table config export
|-- firebase.json               # FlutterFire/Firebase project config
|-- l10n.yaml                   # Flutter localization config
`-- pubspec.yaml                # Flutter package manifest
```

## Getting Started

### Requirements

- Flutter `3.47.9` stable is used in CI (pinned in `.github/actions/setup-flutter/action.yml`).
- Dart SDK `^3.13.0` is required by `pubspec.yaml`.
- Java 21 is used for Android builds in CI.
- Xcode and CocoaPods are required for iOS development.
- Android Studio or Android command-line tools are required for Android development.

### Install dependencies

```sh
flutter pub get
```

### Generate local files when needed

```sh
dart run flutter_launcher_icons
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
```

### Run the app

```sh
flutter run
```

Common platform-specific commands:

```sh
flutter run -d ios
flutter run -d android
```

The committed Firebase platform files are:

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart`

If you create new Firebase apps or rotate Firebase config, regenerate these with FlutterFire tooling and verify push notifications afterwards.

## Development Workflow

Use these checks before opening a pull request:

```sh
flutter analyze
flutter test
```

CI runs `flutter test` on every pull request, then builds a debug APK. It doesn't run `flutter analyze`, so run that yourself.

For Android build verification:

```sh
flutter build apk --debug
```

For release-like local builds:

```sh
flutter build appbundle --release
flutter build ipa --release
```

iOS release builds require valid Apple signing configuration.

## Localization

The app supports English and Norwegian:

- Supported locales are configured in `lib/main.dart`.
- Localization settings are in `l10n.yaml`.
- ARB files live in `lib/generated/l10n/`.
- Generated localization Dart files also live in `lib/generated/l10n/`.

After editing localization strings, regenerate localization output:

```sh
flutter gen-l10n
```

Generated localization files should be updated through tooling rather than edited manually.

## Notifications and Deep Links

Firebase is initialized in `lib/main.dart`, and Firebase Messaging is configured for background message handling. `NotificationService` handles local notification setup and runtime notification behavior.

Deep links are initialized through `DeepLinkService`. Startup continues even if deep link initialization fails, so deep link issues may appear as warnings rather than hard app launch failures.

Relevant routes include:

- `/auth/login`
- `/auth/verify-otp`
- `/onboarding`
- `/home`
- `/explore`
- `/explore/events`
- `/explore/departures`
- `/explore/products`
- `/explore/units`
- `/explore/expenses`
- `/explore/volunteer`
- `/explore/ai-chat`
- `/explore/campus/:campusId`
- `/profile`
- `/events/large/:slug`
- `/controller-mode`

## Build, CI, and Release

Workflows live in `.github/workflows/`:

- `ci.yml` runs on every pull request: `flutter analyze`, `flutter test`, a debug Android build and an unsigned iOS build.
- `release.yml` runs on every push to `main`. It runs the same checks, builds a signed app bundle and IPA, and uploads them to Google Play's internal testing track and to TestFlight. Nothing is uploaded unless the checks and both builds pass.

Promoting a build to production (Google Play) or submitting it for review (App Store) stays a manual step in the store consoles.

### Versions

CI picks the version, so `pubspec.yaml` is not bumped by hand. Claude reads the commits since the last release and judges its size: a **minor** release when it gives students something new (a new screen, feature or capability), otherwise a **patch** (fixes, polish, internal work). So `2.2.16+100` becomes `2.3.0+101` or `2.2.17+101`; the build number always goes up by one. The run summary and the GitHub release say which it chose and why. Then the release uploads both apps, tags the built commit (`v2.3.0+101`) with a GitHub release, and commits `chore(release): 2.3.0+101` to `main`.

- To choose the bump yourself, a major one included, use **Actions → Release → Run workflow** and pick the part (or `gh workflow run release.yml -f bump=major`).
- A `pubspec.yaml` edited by hand to a higher build number ships as written.
- To merge without releasing, put `[skip release]` in the commit or merge message. Changes to only `*.md` files or `docs/` never release.
- BISO's admin (**Settings → App versions**) can block or nudge app versions below a minimum or recommended one. Set the minimum version only after the release is live for everyone in both stores: on Google Play after a 100% rollout, and in the App Store after Apple has released it. Anyone who is blocked before they can download the new version is stuck with nothing to update to.

### Release notes

`tool/release/release_notes.py` has Claude write English and Norwegian notes from the commit messages since the last release (and judge the release's size, above). They become Google Play's release notes (`en-US`, `no-NO`), TestFlight's "What to Test" and the GitHub release. Claude runs through the Claude Code CLI, signed in with `CLAUDE_CODE_OAUTH_TOKEN`, so the notes use Claude subscription usage, not API credits. If Claude Code fails or the subscription's usage limit is reached, the notes list the commit subjects instead, the release is a patch, and the run shows a warning.

TestFlight only takes notes when the app's **TestFlight → Test Information** (beta description and feedback email) is filled in; the upload stops before it starts if it is not.

### iOS signing and export compliance

CI signs with an Apple Distribution certificate and the App Store profiles named in `ios/ExportOptions.plist`: `BISO App Store` (`com.biso.no`) and `BISO Share Extension App Store` (`com.biso.no.BISOShareExtension`). `tool/release/ios_manual_signing.rb` points the Release configuration at them on the CI checkout only, so Xcode keeps automatic signing locally.

The certificate expires after a year. Then create a new one, regenerate both profiles under the same names, and update the `IOS_CERTIFICATE_*` secrets.

`ITSAppUsesNonExemptEncryption` is `NO` in `ios/Runner/Info.plist`, so App Store Connect no longer asks the export compliance questions. That answer holds while the app uses only standard TLS and is not distributed in France.

### Secrets and variables

| Name | What it is |
|------|------------|
| `ANDROID_KEYSTORE_BASE64` | Upload keystore (`.jks`), base64 |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` | Upload keystore credentials |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Play Console service account key (JSON text) |
| `IOS_CERTIFICATE_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD` | Apple Distribution certificate with its private key (`.p12`), base64, and its password |
| `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID` | App Store Connect API key. It needs the App Manager role with access to Certificates, Identifiers & Profiles, or Admin |
| `APPLE_API_PRIVATE_KEY` | That key's `.p8` file, as text or base64-encoded |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude subscription token for the release notes, made with `claude setup-token` (also used by the Claude workflows) |
| `TESTFLIGHT_GROUPS` (variable) | TestFlight groups to add each build to, comma-separated (optional) |

## Current State / Notes for Maintainers

- Appwrite is the long-term backend target, but not every feature is fully Appwrite-native yet.
- Events, jobs, and webshop data still use WordPress/API/function-backed paths.
- Appwrite schema classes live in `lib/schema/appwrite/`, and `appwrite.config.json` contains the exported Appwrite project/table configuration.
- Feature availability may be controlled through Appwrite-backed feature flags.
- Chat screens and services exist, but chat is not currently a bottom navigation tab.
- Generated files should be regenerated through Flutter tooling instead of edited manually.
- Tests live in `test/`. Add focused tests around risky service, model and provider changes.

## Useful Commands

```sh
# Dependencies
flutter pub get

# Analyze and test
flutter analyze
flutter test

# Localization and generated code
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs

# Icons
dart run flutter_launcher_icons

# Run app
flutter run
flutter run -d ios
flutter run -d android

# Android builds
flutter build apk --debug
flutter build apk --release
flutter build appbundle --release

# Release now, bumping the minor version
gh workflow run release.yml -f bump=minor
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to report a bug, set up the
project and get a change merged. Everyone who takes part follows the
[code of conduct](CODE_OF_CONDUCT.md).

## Security

Found a security problem? Don't open an issue. Follow
[SECURITY.md](SECURITY.md).

## License

Copyright (c) 2025-2026 BI Studentorganisasjon (BISO). All rights reserved.

The code is public so anyone can read it, but it isn't open source. You may
not reuse it without written permission from BISO. See [LICENSE](LICENSE).
