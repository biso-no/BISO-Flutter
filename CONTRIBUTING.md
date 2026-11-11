# Contributing to BISO-Flutter

This repository holds the BISO mobile app for iOS and Android. BISO's IT team
maintains it. This page says how to report problems and how to get a change
merged.

## Report a problem or suggest a change

- **Bug or idea:** [open an issue](https://github.com/biso-no/BISO-Flutter/issues/new/choose)
  and pick a template.
- **Security problem:** don't open an issue. Follow [SECURITY.md](SECURITY.md).
- **Keep personal data out.** The repository is public. Don't put students'
  names, email addresses, student numbers or screenshots that show them in
  issues, pull requests, test data or commits.

## Before you write code

Read the [README](README.md). It explains the architecture, where data comes
from, and how the app is built and released.

The backend (Appwrite tables, functions and the API) lives in
[BISO-Sites](https://github.com/biso-no/BISO-Sites). Its developer docs at
[docs.biso.no/developers](https://docs.biso.no/developers) cover the app too,
in [The mobile app](https://docs.biso.no/developers/change-it/the-mobile-app).

## Set up

You need the Flutter version CI uses (`flutter-version` in
`.github/actions/setup-flutter/action.yml`), plus Xcode for iOS and the Android
tools for Android.

```bash
git clone https://github.com/biso-no/BISO-Flutter.git
cd BISO-Flutter
flutter pub get
dart run flutter_launcher_icons
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter run
```

## Make the change

- Branch from `main`. Name the branch after the kind of change:
  `feat/…`, `fix/…`, `chore/…` or `docs/…`.
- Write commit messages as `type(scope): summary`, for example
  `fix(events): show the ticket link on past events`.
- Add every new user-facing string to both `lib/generated/l10n/app_en.arb` and
  `lib/generated/l10n/app_no.arb`, then run `flutter gen-l10n`. Don't edit the
  generated Dart files by hand.
- If the change needs a backend change, such as a new Appwrite table, column
  or function, make that in BISO-Sites and link the two pull requests.
- Never commit secrets: signing keys, keystores, `.env` files, service account
  JSON or App Store Connect keys. The README lists which secrets CI holds.

## Check your work

CI runs the analyzer, the tests, a debug Android build and an unsigned iOS
build on every pull request. Run the first two yourself before you push:

```bash
flutter analyze
flutter test
```

Try the change on a real device or a simulator, on iOS and on Android if it
touches anything platform-specific.

Don't bump the version in `pubspec.yaml`. Every merge to `main` is released to
Google Play internal testing and TestFlight, and the release picks the version.
The README's "Build, CI, and Release" section explains how.

## Open a pull request

- Open it against `main` and fill in the template.
- CI and an automated code review run on every pull request. Answer or fix
  each review comment.
- A maintainer reviews and merges. Smaller, focused pull requests are merged
  faster.

## Terms for contributions

This repository is not open source. [LICENSE](LICENSE) reserves all rights to
BISO. By submitting a contribution (a pull request, a patch or code in an
issue), you:

- confirm that you wrote it, or otherwise have the right to submit it;
- give BISO a permanent, worldwide, free, non-exclusive and irrevocable right
  to use, copy, change, distribute and sublicense it as part of BISO's
  software, on any terms BISO chooses.

Don't submit code copied from somewhere whose license doesn't allow this.

## Code of conduct

Everyone who takes part is expected to follow the
[code of conduct](CODE_OF_CONDUCT.md).
