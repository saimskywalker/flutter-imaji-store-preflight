# imaji_store_preflight

Catch App Store and Google Play rejections in your Flutter project before you
upload: one Dart command lints `Info.plist`, the privacy manifest,
entitlements and `AndroidManifest.xml`, and fails CI on the mistakes that get
builds refused.

[![pub version](https://img.shields.io/pub/v/imaji_store_preflight.svg)](https://pub.dev/packages/imaji_store_preflight)
[![pub points](https://img.shields.io/pub/points/imaji_store_preflight)](https://pub.dev/packages/imaji_store_preflight/score)
[![pub likes](https://img.shields.io/pub/likes/imaji_store_preflight)](https://pub.dev/packages/imaji_store_preflight/score)
[![CI](https://github.com/saimskywalker/flutter-imaji-store-preflight/actions/workflows/ci.yml/badge.svg)](https://github.com/saimskywalker/flutter-imaji-store-preflight/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/saimskywalker/flutter-imaji-store-preflight/blob/main/LICENSE)

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
dart pub global activate imaji_store_preflight
```

Or pin it per project with `flutter pub add --dev imaji_store_preflight` and
run `dart run imaji_store_preflight`.

## Quick start

```bash
cd my_flutter_app
imaji_store_preflight
```

If `~/.pub-cache/bin` is not on your `PATH`, run
`dart pub global run imaji_store_preflight`. In CI, `--sarif --output
preflight.sarif` turns findings into pull request annotations
([GitHub Actions setup](https://github.com/saimskywalker/flutter-imaji-store-preflight/blob/main/doc/github-actions.md)).

## Example output

A fresh `flutter create` app gets one warning: no privacy manifest yet. Here
it is after `flutter pub add image_picker` and a one-line camera purpose
string (`--brief` drops the why/fix text):

```text
$ imaji_store_preflight --brief
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

`imaji_store_preflight --explain <rule-id>` prints the full why, fix, options
and documentation links for one rule.

## Documentation

- [Rules and the store messages they prevent](https://github.com/saimskywalker/flutter-imaji-store-preflight/blob/main/doc/rules.md), including planned rules
- [Command line, configuration and library use](https://github.com/saimskywalker/flutter-imaji-store-preflight/blob/main/doc/configuration.md)
- [GitHub Actions with code scanning](https://github.com/saimskywalker/flutter-imaji-store-preflight/blob/main/doc/github-actions.md)
- [FAQ, limitations and comparisons](https://github.com/saimskywalker/flutter-imaji-store-preflight/blob/main/doc/faq.md)
- [pub.dev page](https://pub.dev/packages/imaji_store_preflight) and [API docs](https://pub.dev/documentation/imaji_store_preflight/latest/)
- [CHANGELOG](https://github.com/saimskywalker/flutter-imaji-store-preflight/blob/main/CHANGELOG.md) and [issues](https://github.com/saimskywalker/flutter-imaji-store-preflight/issues)

## Contributing

The most useful contributions are a rejection you hit that no rule catches
(open an issue with the anonymised reviewer wording or `ITMS-` code and the
public Apple or Google documentation) and corrections to the data tables.
[CONTRIBUTING.md](https://github.com/saimskywalker/flutter-imaji-store-preflight/blob/main/CONTRIBUTING.md)
explains how to add a rule; issues labelled
[good first issue](https://github.com/saimskywalker/flutter-imaji-store-preflight/labels/good%20first%20issue)
are a good place to start.

## Trademarks

Apple, App Store, iOS and Xcode are trademarks of Apple Inc. Google Play and
Android are trademarks of Google LLC. This project is independent and is not
affiliated with, sponsored by or endorsed by Apple or Google; the names are
used only to say which store rules a check is about.

## License

MIT © saimskywalker. See [LICENSE](https://github.com/saimskywalker/flutter-imaji-store-preflight/blob/main/LICENSE).
