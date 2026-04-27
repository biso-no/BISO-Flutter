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
|-- .github/workflows/          # GitHub Actions build/deploy workflow
|-- appwrite.config.json        # Appwrite project/table config export
|-- firebase.json               # FlutterFire/Firebase project config
|-- l10n.yaml                   # Flutter localization config
`-- pubspec.yaml                # Flutter package manifest
```

## Getting Started

### Requirements

- Flutter `3.32.8` stable is used in CI.
- Dart SDK `^3.8.1` is required by `pubspec.yaml`.
- Java 17 is used for Android builds in CI.
- Xcode and CocoaPods are required for iOS development.
- Android Studio or Android command-line tools are required for Android development.

### Install dependencies

```sh
flutter pub get
```

### Generate local files when needed

```sh
flutter pub run intl_utils:generate
flutter pub run flutter_launcher_icons
flutter pub run build_runner build --delete-conflicting-outputs
```

`build_runner` is currently allowed to fail in CI, so treat failures there as feature-specific unless you are working on generated code.

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

There are currently no committed tests, so `flutter test` is mostly a smoke check until test coverage is added.

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
flutter pub run intl_utils:generate
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

GitHub Actions are configured in `.github/workflows/build.yml`.

### Android CI

On pushes to `main` and version tags, CI:

1. Sets up Java 17 and Flutter `3.32.8`.
2. Runs `flutter pub get`.
3. Generates launcher icons and localization files.
4. Runs `build_runner`.
5. Runs tests.
6. Builds Android AAB and APK with version `2.0.1+82`.
7. Uploads the AAB to the Google Play internal track.
8. Attaches the APK to a GitHub release.

Required Android repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`

### iOS Fastlane

Fastlane configuration lives in `ios/fastlane/`. The main beta lane builds and uploads to TestFlight:

```sh
cd ios
bundle exec fastlane beta
```

The Fastlane setup supports App Store Connect API authentication and either match-based signing or manual signing fallback.

Useful iOS/TestFlight secrets and environment variables:

- `APPLE_API_KEY_ID`: App Store Connect API key ID.
- `APPLE_API_ISSUER_ID`: App Store Connect API issuer ID.
- `APPLE_API_PRIVATE_KEY`: App Store Connect API private key content.
- `APP_STORE_CONNECT_API_KEY_ID`: alternate App Store Connect API key ID name supported by Fastlane.
- `APP_STORE_CONNECT_API_ISSUER_ID`: alternate App Store Connect API issuer ID name supported by Fastlane.
- `APP_STORE_CONNECT_API_KEY`: alternate base64 API key content supported by Fastlane.
- `APPLE_ID`: Apple ID email, used as fallback when API key auth is not available.
- `APP_STORE_CONNECT_TEAM_ID`: App Store Connect team ID.
- `DEVELOPER_TEAM_ID`: Apple Developer team ID.
- `MATCH_PASSWORD`: Fastlane match password.
- `MATCH_GIT_BASIC_AUTHORIZATION`: GitHub token or base64 authorization for match repo access.
- `MATCH_SSH_KEY`: SSH key option for match repo access.
- `PROVISIONING_PROFILE_NAME` or `PROVISIONING_PROFILE_SPECIFIER`: manual signing fallback.

The previous manual CI setup also referenced these iOS secrets; keep them available if your deployment flow still depends on manually installed certificates and profiles:

- `IOS_CERTIFICATE_P12_BASE64`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE_BASE64`

## Current State / Notes for Maintainers

- Appwrite is the long-term backend target, but not every feature is fully Appwrite-native yet.
- Events, jobs, and webshop data still use WordPress/API/function-backed paths.
- Appwrite schema classes live in `lib/schema/appwrite/`, and `appwrite.config.json` contains the exported Appwrite project/table configuration.
- Feature availability may be controlled through Appwrite-backed feature flags.
- Chat screens and services exist, but chat is not currently a bottom navigation tab.
- Generated files should be regenerated through Flutter tooling instead of edited manually.
- No test suite is currently committed. Add focused tests around risky service/model/provider changes as coverage grows.

## Useful Commands

```sh
# Dependencies
flutter pub get

# Analyze and test
flutter analyze
flutter test

# Localization and generated code
flutter pub run intl_utils:generate
flutter pub run build_runner build --delete-conflicting-outputs

# Icons
flutter pub run flutter_launcher_icons

# Run app
flutter run
flutter run -d ios
flutter run -d android

# Android builds
flutter build apk --debug
flutter build apk --release
flutter build appbundle --release

# iOS beta upload
cd ios
bundle exec fastlane beta
```
