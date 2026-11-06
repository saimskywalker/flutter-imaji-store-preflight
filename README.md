# storehound

Catch App Store and Google Play rejections in your Flutter project before you
upload: one Dart command lints `Info.plist`, the privacy manifest,
entitlements and `AndroidManifest.xml`, and fails CI on the mistakes that get
builds refused.

[![pub version](https://img.shields.io/pub/v/storehound.svg)](https://pub.dev/packages/storehound)
[![pub points](https://img.shields.io/pub/points/storehound)](https://pub.dev/packages/storehound/score)
[![pub likes](https://img.shields.io/pub/likes/storehound)](https://pub.dev/packages/storehound/score)
[![CI](https://github.com/saimskywalker/storehound/actions/workflows/ci.yml/badge.svg)](https://github.com/saimskywalker/storehound/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/saimskywalker/storehound/blob/main/LICENSE)

## Why

- A missing purpose string or a privacy manifest that never reaches the bundle
  compiles, passes every test, and only shows up as an `ITMS-` email after
  upload.
- A vague purpose string or an unjustified background mode costs you a whole
  review cycle.
- Play refuses an update below the target API deadline, usually during an
  urgent fix.

It reads the files you ship and answers in about a second. No Xcode, no macOS
runner, no build.

## Install

```bash
dart pub global activate storehound
```

Or pin it per project with `flutter pub add --dev storehound` and
run `dart run storehound`.

### Coming from imaji_store_preflight

This package was renamed. Replace `imaji_store_preflight` with `storehound` in
`dev_dependencies` (or `dart pub global activate storehound`), run
`storehound` instead of `imaji_store_preflight`, and rename
`imaji_store_preflight.yaml` to `storehound.yaml`. Rules and options are
unchanged.

## Quick start

```bash
cd my_flutter_app
storehound
```

If `~/.pub-cache/bin` is not on your `PATH`, run
`dart pub global run storehound`. Exit code `0` means clean, `1`
means findings at or above `--fail-on` (default `error`), `2` means a usage or
configuration problem.

## Example output

A fresh `flutter create` app gets one warning: no privacy manifest yet. Here
it is after `flutter pub add image_picker` and a one-line camera purpose
string (`--brief` drops the why/fix text):

```text
$ storehound --brief
privacy-manifest-present — The app target ships a PrivacyInfo.xcprivacy
  warning  ios/Runner/Info.plist
    No privacy manifest at ios/Runner/PrivacyInfo.xcprivacy (or the path
    configured under `paths.privacy_manifest`).

purpose-string-missing — Linked plugins have the purpose strings they need
  error  ios/Runner/Info.plist
    `NSPhotoLibraryUsageDescription` is missing, but image_picker needs it.
  error  ios/Runner/Info.plist
    `NSMicrophoneUsageDescription` is missing, but image_picker needs it.

purpose-string-quality — Purpose strings name a feature and give an example, not restate the permission
  error  ios/Runner/Info.plist:5
    `NSCameraUsageDescription` only restates the permission; name the feature
    that uses it and give an example. Current text: "This app needs camera
    access."

✗ 15 rules checked: 3 errors, 1 warning, 0 info. Failing: findings at or above `error`.
```

The exit code is `1`, so CI fails. Without `--brief` each finding also says
why it matters, how to fix it, and links Apple's or Google's documentation.
`--format json` and `--sarif` give the same findings in machine-readable form.

## Run it in CI

This job fails the build on errors and shows each finding as a code scanning
annotation on the pull request:

```yaml
name: Store preflight
on: [push, pull_request]

jobs:
  preflight:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write   # upload SARIF
    steps:
      - uses: actions/checkout@v6
      - uses: dart-lang/setup-dart@v1
      - run: dart pub global activate storehound '^0.2.0'
      - run: dart pub global run storehound --sarif --output preflight.sarif
      - uses: github/codeql-action/upload-sarif@v4
        if: always()           # upload even when the check fails the job
        with:
          sarif_file: preflight.sarif
          category: storehound
```

No macOS runner needed. Code scanning needs a public repository or GitHub
Advanced Security; without it, drop the upload step and read the text output
in the job log.
[More on CI](https://github.com/saimskywalker/storehound/blob/main/doc/github-actions.md),
including how `android-target-sdk` behaves on a Dart-only runner.

## What it checks

| Rule | Catches |
|---|---|
| `purpose-string-missing` | ITMS-90683 "Missing purpose string" for plugins like `image_picker`, `camera`, `geolocator` |
| `purpose-string-quality` | Guideline 5.1.1(ii): a purpose string that only restates the permission |
| `privacy-manifest-present` | ITMS-91053: no `PrivacyInfo.xcprivacy`, or one missing from Copy Bundle Resources |
| `privacy-manifest-values` | Data types, purposes and reason codes that are not Apple's exact values |
| `privacy-manifest-tracking` | `NSPrivacyTracking` contradicting the entries or tracking domains |
| `privacy-manifest-sdk-data` | "Collects nothing" while Firebase, AdMob, Sentry or another known SDK is linked |
| `tracking-usage-description` | "Add for Review" refused over `NSUserTrackingUsageDescription` vs declared tracking |
| `background-modes-justified` | Guideline 2.5.4: background modes with no feature behind them |
| `push-entitlement` | Push SDK linked without `aps-environment`, so notifications never arrive |
| `export-options-build-number` | Xcode silently bumping `CFBundleVersion` at export |
| `bundle-localizations` | `CFBundleLocalizations` out of sync with your ARB locales |
| `android-target-sdk` | `targetSdk` below Google Play's current deadline |
| `android-16kb-page-size` | A build toolchain without 16 KB page-size support |
| `android-picker-queries` | `file_picker` without an `OPEN_DOCUMENT` `<queries>` entry |
| `unreadable-file` | A config file that does not parse, so rules would silently pass |

`storehound --explain <rule-id>` prints the full why, fix, options
and documentation links for one rule.

### Your own checks

Pins only your app cares about go under `checks:` in `storehound.yaml`, each
with a reason, and are reported like any rule as `check:<name>`:

```yaml
checks:
  no-backup:
    file: android_manifest
    element: application
    attribute: android:allowBackup
    equals: "false"
    reason: "Tokens live in shared preferences."
```

They work on `Info.plist` keys and `AndroidManifest.xml` attributes; see
[Project checks](https://github.com/saimskywalker/storehound/blob/main/doc/configuration.md#project-checks)
for the operators.

## Is it noisy on a real app?

It should not be. CI runs it with `--fail-on info` on
[a production-shaped fixture](https://github.com/saimskywalker/storehound/tree/main/test/fixtures/production_app)
(two flavors, SwiftPM only, AGP 9, separate Debug and Release entitlements,
a large commented `Info.plist`) and expects no findings at all, and the
tests change one thing at a time in it to check that each mistake is still
caught. If it reports something on your app that is not a real problem,
please open an issue with an anonymised copy of the lines involved.

## Documentation

- [Rules and the store messages they prevent](https://github.com/saimskywalker/storehound/blob/main/doc/rules.md), including planned rules
- [Command line, configuration and library use](https://github.com/saimskywalker/storehound/blob/main/doc/configuration.md)
- [GitHub Actions with code scanning](https://github.com/saimskywalker/storehound/blob/main/doc/github-actions.md)
- [FAQ, limitations and comparisons](https://github.com/saimskywalker/storehound/blob/main/doc/faq.md)
- [pub.dev page](https://pub.dev/packages/storehound) and [API docs](https://pub.dev/documentation/storehound/latest/)
- [CHANGELOG](https://github.com/saimskywalker/storehound/blob/main/CHANGELOG.md) and [issues](https://github.com/saimskywalker/storehound/issues)

## Contributing

The most useful contributions are a rejection you hit that no rule catches
(open an issue with the anonymised reviewer wording or `ITMS-` code and the
public Apple or Google documentation) and corrections to the data tables.
[CONTRIBUTING.md](https://github.com/saimskywalker/storehound/blob/main/CONTRIBUTING.md)
explains how to add a rule; issues labelled
[good first issue](https://github.com/saimskywalker/storehound/labels/good%20first%20issue)
are a good place to start. Questions and ideas that are not bugs go to
[Discussions](https://github.com/saimskywalker/storehound/discussions).

## Trademarks

Apple, App Store, iOS and Xcode are trademarks of Apple Inc. Google Play and
Android are trademarks of Google LLC. This project is independent and is not
affiliated with, sponsored by or endorsed by Apple or Google; the names are
used only to say which store rules a check is about.

## License

MIT © saimskywalker. See [LICENSE](https://github.com/saimskywalker/storehound/blob/main/LICENSE).
