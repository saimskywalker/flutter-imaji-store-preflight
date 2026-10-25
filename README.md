# imaji_store_preflight

[![pub version](https://img.shields.io/pub/v/imaji_store_preflight.svg)](https://pub.dev/packages/imaji_store_preflight)
[![pub points](https://img.shields.io/pub/points/imaji_store_preflight)](https://pub.dev/packages/imaji_store_preflight/score)
[![CI](https://github.com/saimskywalker/flutter-imaji-store-preflight/actions/workflows/ci.yml/badge.svg)](https://github.com/saimskywalker/flutter-imaji-store-preflight/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Catch App Store and Google Play rejections before you upload.** One Dart
command lints your Flutter project's `Info.plist`, privacy manifest,
entitlements and `AndroidManifest.xml`, and fails CI on the mistakes that get
builds refused at upload or rejected in review.

A missing purpose string, a privacy manifest that never reaches the bundle, a
background mode with no feature behind it: these compile, pass every test, and
only surface after upload, in an `ITMS-` email or a rejection that costs you a
review cycle. `imaji_store_preflight` reads the files you ship and catches them
in about a second, on any machine that has Dart. No Xcode, no macOS runner, no
build.

[Quick start](#quick-start-30-seconds) ·
[Problems this solves](#problems-this-solves) ·
[Rules](#rules) ·
[GitHub Actions](#github-actions) ·
[Configuration](#configuration) ·
[FAQ and limitations](#faq-and-limitations)

## Quick start (30 seconds)

```bash
# Once, globally (puts imaji_store_preflight on your PATH via ~/.pub-cache/bin):
dart pub global activate imaji_store_preflight
cd my_flutter_app && imaji_store_preflight

# …or pinned per project, as a dev dependency:
flutter pub add --dev 'imaji_store_preflight:^0.1.0'
dart run imaji_store_preflight
```

If `~/.pub-cache/bin` is not on your `PATH`, run
`dart pub global run imaji_store_preflight` instead.

On a fresh `flutter create` app it reports a single warning: there is no
privacy manifest yet. Here is a real run after adding `image_picker` and a
one-line camera purpose string (`--brief` drops the explanations):

```text
$ flutter pub add image_picker
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
  error  ios/Runner/Info.plist:29
    `NSCameraUsageDescription` only restates the permission; name the feature
    that uses it and give an example. Current text: "This app needs camera
    access."

✗ 15 rules checked: 3 errors, 1 warning, 0 info. Failing: findings at or above `error`.
```

The exit code is `1`, so CI fails. Without `--brief`, every rule also says
**why** it matters, **how to fix** it, and links Apple's or Google's
documentation:

```text
purpose-string-missing — Linked plugins have the purpose strings they need
  error  ios/Runner/Info.plist
    `NSPhotoLibraryUsageDescription` is missing, but image_picker needs it.
  …
  why: App Store Connect rejects an upload whose code references a protected
  resource without its Info.plist purpose string (ITMS-90683, "Missing purpose
  string"), and iOS terminates the app the first time it asks for a permission
  whose string is missing. Neither shows up in a simulator run that never
  reaches the permission prompt.
  fix: Add the key to ios/Runner/Info.plist with a sentence that names the
  feature and gives an example (see `purpose-string-quality`). Extend the plugin
  table with the `required_by_plugin` option.
  docs: https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources
```

`--format json` and `--sarif` give the same findings in machine-readable form.

## Problems this solves

If you got one of these, this is the rule that catches it before upload.
Planned rules link their roadmap issue.

| Store message or rejection | Caught by | Related upstream threads |
|---|---|---|
| ITMS-90683: Missing purpose string in Info.plist, for a plugin you use (`image_picker`, `camera`, `geolocator`, `local_auth`, …) | `purpose-string-missing` | |
| ITMS-90683 for an API your app never calls, referenced by a dependency | planned: [#12](https://github.com/saimskywalker/flutter-imaji-store-preflight/issues/12), [#25](https://github.com/saimskywalker/flutter-imaji-store-preflight/issues/25) | [flutter/flutter#21941](https://github.com/flutter/flutter/issues/21941) |
| Guideline 5.1.1(ii): the purpose string does not explain how the app uses the data | `purpose-string-quality` | |
| ITMS-91053: Missing API declaration: your app's own privacy manifest is missing, not in Copy Bundle Resources, or uses a value Apple does not define | `privacy-manifest-present`, `privacy-manifest-values` | [flutter/flutter#145269](https://github.com/flutter/flutter/issues/145269), [flutter/flutter#143232](https://github.com/flutter/flutter/issues/143232) |
| ITMS-91053 for required-reason APIs called from FFI or native assets | planned: [#17](https://github.com/saimskywalker/flutter-imaji-store-preflight/issues/17) | [flutter/flutter#147186](https://github.com/flutter/flutter/issues/147186), [flutter/flutter#140966](https://github.com/flutter/flutter/issues/140966) |
| ITMS-91061: Missing privacy manifest for a third-party SDK | planned: [#13](https://github.com/saimskywalker/flutter-imaji-store-preflight/issues/13) | [firebase/flutterfire#16937](https://github.com/firebase/flutterfire/issues/16937) |
| Privacy manifest declares no collected data while Firebase, AdMob, Sentry or another known SDK is linked | `privacy-manifest-sdk-data` | |
| App Store Connect refuses "Add for Review": `NSUserTrackingUsageDescription` present while no tracking is declared | `tracking-usage-description` | |
| Guideline 2.5.4: "unable to locate any features that require persistent audio" | `background-modes-justified` | |
| Missing Push Notification Entitlement, or pushes that never arrive, with a push SDK linked | `push-entitlement` | [flutter/flutter#14182](https://github.com/flutter/flutter/issues/14182) |
| Google Play refuses an update below the target API level deadline | `android-target-sdk` | |
| Google Play 16 KB page-size requirement (the build toolchain; prebuilt `.so` files need the built APK/AAB) | `android-16kb-page-size` | |
| Google Play Photo and Video Permissions policy (`READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO`) | planned: [#10](https://github.com/saimskywalker/flutter-imaji-store-preflight/issues/10) | [flutter/flutter#173536](https://github.com/flutter/flutter/issues/173536), [flutter/flutter#171494](https://github.com/flutter/flutter/issues/171494) |
| Google Play: manifest does not include the `AD_ID` permission | planned: [#18](https://github.com/saimskywalker/flutter-imaji-store-preflight/issues/18) | [googleads/googleads-mobile-flutter#922](https://github.com/googleads/googleads-mobile-flutter/issues/922) |
| Google Play "edge-to-edge may not display for all users" warnings | planned: [#20](https://github.com/saimskywalker/flutter-imaji-store-preflight/issues/20) | [flutter/flutter#192921](https://github.com/flutter/flutter/issues/192921), [flutter/flutter#183372](https://github.com/flutter/flutter/issues/183372) |

## Rules

| Rule | Checks | Prevents |
|---|---|---|
| `privacy-manifest-present` | `PrivacyInfo.xcprivacy` exists (warning) and is in Copy Bundle Resources (error) | ITMS-91053 at upload when the app's own code uses a required-reason API; a manifest that never reaches the bundle |
| `privacy-manifest-values` | Data types, purposes, required-reason API categories and reason codes are Apple's exact values | A misspelt type that silently declares nothing; ITMS-91053 for an unapproved reason |
| `privacy-manifest-tracking` | `NSPrivacyTracking` agrees with each entry's Tracking flag and with `NSPrivacyTrackingDomains` | A manifest that contradicts itself and the privacy label |
| `privacy-manifest-sdk-data` | Collected data covers what linked SDKs (Firebase, AdMob, StoreKit, Sentry, …) collect, read from `pubspec.lock` | "Collects nothing" next to an analytics SDK — a label/manifest mismatch reviewers flag |
| `tracking-usage-description` | `NSUserTrackingUsageDescription` exists exactly when `PrivacyInfo.xcprivacy` declares tracking; warns when `app_tracking_transparency` is linked without it | App Store Connect refusing "Add for Review"; an ATT request that terminates the app |
| `purpose-string-missing` | Plugins that touch the camera, microphone, photos, location, contacts, Face ID… have their `NS…UsageDescription`; Always location also has When-In-Use | ITMS-90683 "Missing purpose string"; a crash at the first permission request |
| `purpose-string-quality` | Purpose strings name a feature and give an example instead of restating the permission | Guideline 5.1.1(ii) rejection ("needs camera access") |
| `background-modes-justified` | Every `UIBackgroundModes` entry is a mode Apple defines and has a justification recorded under `allow` — an error when no linked plugin uses the mode, a warning when one plausibly does; `processing` also needs `BGTaskSchedulerPermittedIdentifiers` | Guideline 2.5.4 rejection ("unable to locate any features that require persistent audio") |
| `export-options-build-number` | Every `ExportOptions*.plist` with method `app-store` / `app-store-connect` sets `manageAppVersionAndBuildNumber` to false (it defaults to YES) | Xcode silently bumping `CFBundleVersion` at export |
| `bundle-localizations` | `CFBundleLocalizations` matches your ARB locales | Store listing and system prompts stuck in one language, or a listing that claims a language you don't ship |
| `push-entitlement` | Apps using push (FCM, OneSignal, Airship, `remote-notification`) carry `aps-environment`, set to `development` or `production` | Notifications that never arrive, with nothing failing |
| `android-picker-queries` | `file_picker` apps declare an `OPEN_DOCUMENT` `<queries>` intent | A file picker that never opens on some Android ROMs |
| `android-target-sdk` | `targetSdk` meets Google Play's current deadline (dated table, overridable; follows `flutter.targetSdkVersion` into your Flutter SDK) | Play Console refusing your update — usually during an urgent fix |
| `android-16kb-page-size` | When `targetSdk` is 35+ or cannot be determined: Android Gradle Plugin ≥ 8.5.1 (or legacy packaging), NDK r28+ for your own native code | Play not letting you release an update without 16 KB page-size support, from 1 February 2027 ([Android guide](https://developer.android.com/guide/practices/page-sizes#google-play-compatibility-requirement)) |
| `unreadable-file` | Every file above parses (binary plists get a `plutil` hint) | Rules silently passing a file nobody could read |

`imaji_store_preflight --list-rules` prints this list;
`imaji_store_preflight --explain <rule-id>` prints the full why, fix, options
and documentation links for one rule.

## Command line

```text
imaji_store_preflight [options] [project-dir]

-p, --project=<dir>     Flutter project root to check (default ".")
-c, --config=<file>     Configuration file (default: imaji_store_preflight.yaml in the project)
-f, --format            text (default), json, sarif
    --sarif             Shorthand for --format sarif
-o, --output=<file>     Write the report to a file; a one-line summary goes to stderr
    --fail-on           error (default), warning, info, never
    --today=YYYY-MM-DD  Date deadlines are measured against (reproducible runs)
    --brief             Text output without the why/fix explanations
    --[no-]color        Colour text output (default: when stdout is a terminal and NO_COLOR is unset)
    --list-rules        List every rule
    --explain=<rule-id> Explain one rule
    --version           Print the version
-h, --help              Show the usage
```

**Exit codes:** `0` no finding at or above `--fail-on`; `1` at least one;
`2` usage error (including an unknown `--explain` rule, a bad `--today`, or an
`--output` file that cannot be written), invalid configuration, or not a
Flutter project (no `pubspec.yaml`, `ios/` or `android/`).

Finding locations in every output format are relative to the working
directory when the project is inside it (otherwise to the project root), so in
a monorepo run it from the repository root with `--project apps/my_app` and the
locations (and SARIF annotations) point at the right files.

## Configuration

Optional. Put `imaji_store_preflight.yaml` next to `pubspec.yaml`:

```yaml
# Lowest severity that fails the run: error (default), warning, info, never.
fail_on: error

# Only needed when your layout differs from `flutter create`.
paths:
  info_plist: ios/Runner/Info.plist
  privacy_manifest: ios/Runner/PrivacyInfo.xcprivacy
  entitlements: [ios/Runner/Runner.entitlements]       # default: ios/Runner/*.entitlements
  export_options: [ios/ExportOptions.plist]            # default: every ExportOptions*.plist found
  android_manifest: android/app/src/main/AndroidManifest.xml
  app_gradle: android/app/build.gradle.kts
  arb_dir: lib/l10n                                    # default: arb-dir from l10n.yaml

rules:
  # Turning a rule off REQUIRES a reason. `bundle-localizations: false` is an error.
  bundle-localizations:
    enabled: false
    reason: English-only app; no ARB files besides app_en.arb.

  # Change a rule's severity for every finding it reports.
  push-entitlement:
    severity: error

  # Rule options (see --explain <rule-id>).
  background-modes-justified:
    allow:
      audio: "Play any track, lock the device: playback continues on the lock screen."
  android-target-sdk:
    warn_days: 120
    deadlines:              # add a newly announced deadline, or an extension Google granted you
      - api: 37
        from: 2027-08-31
  privacy-manifest-sdk-data:
    sdk_data_types:         # extend or override the SDK -> data type table
      my_analytics_plugin: [ProductInteraction, DeviceID]
  purpose-string-quality:
    min_words: 8
    app_names: [MyApp]
    extra_example_markers: ["like"]

# Accept specific findings. A reason is REQUIRED, and shows in every report.
ignore:
  - rule: purpose-string-quality
    path: ios/Runner/Info.plist                # optional; a trailing / matches a directory
    match: NSBluetoothAlwaysUsageDescription   # optional; substring of the message
    reason: Wording approved by App Review in the 2.3 submission.
```

Unknown keys, unknown rule ids and options of the wrong type are errors (exit
code 2) with the line number, so a typo cannot silently switch a check off.
`ignore` entries that match nothing are listed at the end of the text report.

| Rule | Options |
|---|---|
| `privacy-manifest-values` | `extra_data_types`, `extra_purposes`, `extra_api_reasons` (category → reasons) |
| `privacy-manifest-sdk-data` | `sdk_data_types` (package → data types; `[]` disables a built-in entry) |
| `purpose-string-missing` | `required_by_plugin` (package → Info.plist keys) |
| `purpose-string-quality` | `min_words`, `require_example`, `app_names`, `extra_example_markers` |
| `background-modes-justified` | `allow` (mode → justification), `extra_evidence` (mode → packages) |
| `android-picker-queries` | `plugins` (extra file-picker packages) |
| `android-target-sdk` | `target_sdk`, `deadlines` (`api`, `from`), `warn_days` |

## GitHub Actions

Findings show up as annotations on the pull request through code scanning:

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
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub global activate imaji_store_preflight '^0.1.0'
      - run: dart pub global run imaji_store_preflight --sarif --output preflight.sarif
      - uses: github/codeql-action/upload-sarif@v3
        if: always()           # upload even when the check fails the job
        with:
          sarif_file: preflight.sarif
          category: imaji-store-preflight
```

If `android/app/build.gradle(.kts)` sets `targetSdk = flutter.targetSdkVersion`
(the `flutter create` default), the value lives in the Flutter SDK, which the
tool finds through `.dart_tool/package_config.json` or `FLUTTER_ROOT`. With
only Dart on the runner neither exists, so `android-target-sdk` reports an
`info` finding instead of checking the deadline. Set its `target_sdk` option,
or install Flutter (e.g. `subosito/flutter-action`) and run `flutter pub get`
before the check.

Without code scanning (it needs a public repository or GitHub Advanced
Security), drop the upload step and use the default text output — the job log
then carries the why/fix for every finding. Suppressed findings are written to
the SARIF with their reason, so code scanning shows them as dismissed.

## Use it as a library

```dart
import 'package:imaji_store_preflight/imaji_store_preflight.dart';

void main() {
  final report = runPreflight('path/to/flutter_app');
  print(renderText(report));
}
```

`renderJson` (stable schema, `schemaVersion: 1`) and `renderSarif` are exported
too, and `Rule` is the extension point — see [CONTRIBUTING.md](CONTRIBUTING.md).

## How it compares

It complements the checks you already have; it does not replace them.

- **Upload processing in App Store Connect / Xcode "Validate App"** is the
  authority on `ITMS-` errors, but needs macOS, a signed archive and a
  finished build. It does not judge purpose-string wording or look at
  Android.
- **[fastlane precheck](https://docs.fastlane.tools/actions/precheck/)**
  checks your App Store *metadata* (description, keywords, URLs) for
  rejection-prone text. `imaji_store_preflight` checks the *configuration
  files in your project*, so the two do not overlap.
- **Google Play Console** tells you about target API level and 16 KB
  page-size problems when you upload a bundle. This tool tells you on the pull
  request that introduces them.

## FAQ and limitations

**Does it need macOS or Xcode?** No. It reads files; it never builds. Run it on
Linux runners, in a pre-commit hook, anywhere Dart runs.

**Will it find every reason for a rejection?** No. It finds contradictions and
omissions in the configuration files listed above. It does not see your
app's behaviour, your store listing or your binary. Treat a clean run as
"none of these known mistakes", not as an approval.

**Does it read my dependencies' own privacy manifests or scan native code for
required-reason APIs?** Not yet. It reads `pubspec.lock` to know which
plugins are linked; checking their manifests and native code is planned in
[#13](https://github.com/saimskywalker/flutter-imaji-store-preflight/issues/13)
and
[#17](https://github.com/saimskywalker/flutter-imaji-store-preflight/issues/17).

**Flavors, app extensions, monorepos?** Each run checks one `Info.plist`, one
privacy manifest and one `AndroidManifest.xml` (configurable under `paths`).
Use `--project` for each app in a monorepo; checking every flavor and
extension in one run is planned in
[#15](https://github.com/saimskywalker/flutter-imaji-store-preflight/issues/15).

**My Info.plist is a binary plist.** Xcode reads both formats; this tool reads
XML and says so clearly. Convert once with `plutil -convert xml1 Info.plist` —
XML is also what makes the file reviewable in a diff.

**A heuristic is wrong for my app.** Add an `ignore` entry with the reason, or
tune the rule's options. If the heuristic is wrong in general, please open an
issue with an anonymised example — the purpose-string and SDK tables get
better with real cases.

**Why does turning a rule off need a reason?** Because the next person to read
the config will want to turn it back on, and a reason is the only thing that
tells them whether that is safe.

**Apple added a new data type / Google moved a deadline.** Use
`extra_data_types` / `deadlines` until a release catches up, and open an issue.
The tables cite the documentation they came from.

**Does it check localized `InfoPlist.strings` purpose strings?** Not yet; only
the base `Info.plist` values.

**Does `privacy-manifest-sdk-data` know every SDK?** No — it knows common
Flutter plugins and is deliberately conservative (a type is listed only when
the SDK collects it by default). Extend it with `sdk_data_types`.

**Is 16 KB alignment fully checked?** Only the build toolchain, from source.
Prebuilt `.so` files inside plugins can only be checked in the built APK/AAB —
use an ELF alignment check such as
[android-imaji-16kb-alignment](https://github.com/saimskywalker/android-imaji-16kb-alignment).

## Contributing

The most useful contributions are **a rejection you hit that no rule
catches** (open an issue with the anonymised reviewer wording or `ITMS-` code
and the public Apple or Google documentation) and **corrections to the data
tables** (privacy vocabulary, the SDK → data-type map, Play deadlines).
[CONTRIBUTING.md](CONTRIBUTING.md) explains how to add a rule and which
commands CI runs; issues labelled
[good first issue](https://github.com/saimskywalker/flutter-imaji-store-preflight/labels/good%20first%20issue)
are a good place to start.

## Support

If this saved you a review cycle, a ⭐ on the repository helps other Flutter
developers find it.

## Trademarks

Apple, App Store, iOS and Xcode are trademarks of Apple Inc. Google Play and
Android are trademarks of Google LLC. This project is independent and is not
affiliated with, sponsored by or endorsed by Apple or Google; the names are
used only to say which store rules a check is about.

## License

MIT © saimskywalker. See [LICENSE](LICENSE).
