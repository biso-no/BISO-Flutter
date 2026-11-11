# Security policy

## Report a vulnerability

Email **[it@biso.no](mailto:it@biso.no)** with "Security" in the subject line.

Don't open a public issue, pull request or discussion about it. This
repository is public, so anyone could read it there.

Include:

- what you found and where: the screen in the app, or the file in this
  repository;
- the steps to reproduce it, with the app version, the phone and its
  operating system version;
- what an attacker could do with it;
- your name or handle, if you'd like to be credited.

## What happens next

BISO's IT team aims to:

1. confirm we've received your report within five working days;
2. tell you whether we can reproduce it, and what we plan to do;
3. tell you when it's fixed.

Please keep the details private until we've fixed the problem, or until 90
days have passed, whichever comes first. If we need more time, we'll ask.

BISO is a student organisation and doesn't pay bug bounties. If you'd like,
we'll thank you by name when the fix is out.

## Scope

In scope is the code in this repository and the BISO app built from it, as
published on the App Store and Google Play. Only the latest version in the
stores gets fixes.

The app talks to BISO's backend (appwrite.biso.no and api.biso.no). Problems
there are covered by the
[BISO-Sites security policy](https://github.com/biso-no/BISO-Sites/security/policy).
You report to the same address.

Out of scope:

- Bugs in other companies' services that the app uses, such as Firebase,
  Apple's and Google's wallets, or iOS and Android themselves. Report those to
  the company. A mistake in how BISO has set them up is in scope.
- Attacks that need physical access to an unlocked phone, or a jailbroken or
  rooted phone.
- Denial-of-service and load testing, spam, and social engineering of BISO
  staff, volunteers or members.
- Findings from automated scanners that don't show a real impact.

## Rules for testing

- Use only accounts and data that are yours. Don't open, change or delete
  anyone else's data. If you come across personal data by accident, stop,
  don't keep a copy, and say so in your report.
- Don't complete real orders or payments to test purchases or memberships.
- Don't do anything that slows down or breaks the services for other people.

If you follow these rules and report in good faith, BISO won't take legal
action against you for your research.
