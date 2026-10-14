# imaji_store_preflight — catch App Store & Google Play rejections in Flutter projects

[![CI](https://github.com/saimskywalker/flutter-imaji-store-preflight/actions/workflows/ci.yml/badge.svg)](https://github.com/saimskywalker/flutter-imaji-store-preflight/actions/workflows/ci.yml)

**Your build passed CI and still got rejected.**

Not for a crash, and not for a failing test — for a contradiction in the
configuration you ship: a privacy manifest that says the app collects nothing
next to an analytics SDK, a tracking purpose string while tracking is declared
off, a background mode the reviewer could not find a feature for, a purpose
string that just restates the permission. These compile cleanly, pass every
test, and cost a full review cycle each.

`imaji_store_preflight` is a Dart CLI that reads your Flutter project's
store-facing configuration — `ios/Runner/Info.plist`, `PrivacyInfo.xcprivacy`,
entitlements, `ExportOptions.plist`, `android/app/src/main/AndroidManifest.xml`,
the Gradle scripts and `pubspec.lock` — and fails CI on the contradictions
reviewers reject. Every rule says **why it matters** (which rejection or silent
failure it prevents) and **how to fix it**, with a link to Apple's or Google's
documentation.

It is pure Dart: no Xcode, no macOS runner, no build. It runs in about a
second on an `ubuntu-latest` runner.

## Quick start (30 seconds)

```bash
# Once, globally:
dart pub global activate imaji_store_preflight
cd my_flutter_app && imaji_store_preflight

# …or pinned per project, as a dev dependency:
flutter pub add --dev imaji_store_preflight
dart run imaji_store_preflight
```

Example output:

```text
tracking-usage-description — NSUserTrackingUsageDescription is present exactly when tracking is
  error  ios/Runner/Info.plist:17
    `NSUserTrackingUsageDescription` is present while
    ios/Runner/PrivacyInfo.xcprivacy declares `NSPrivacyTracking` false.
  why: App Store Connect refuses "Add for Review" for a build that carries
  `NSUserTrackingUsageDescription` while the app declares no tracking — ...
  fix: Treat the purpose string, `NSPrivacyTracking` and the privacy label as
  one decision. ...

✗ 14 rules checked: 3 errors, 1 warning, 0 info. Failing: findings at or above `error`.
```

## Rules

| Rule | Checks | Prevents |
|---|---|---|
| `privacy-manifest-present` | `PrivacyInfo.xcprivacy` exists and is in Copy Bundle Resources | ITMS-91053 at upload; a manifest that never reaches the bundle |
| `privacy-manifest-values` | Data types, purposes, required-reason API categories and reason codes are Apple's exact values | A misspelt type that silently declares nothing; ITMS-91053 for an unapproved reason |
| `privacy-manifest-tracking` | `NSPrivacyTracking` agrees with each entry's Tracking flag and with `NSPrivacyTrackingDomains` | A manifest that contradicts itself and the privacy label |
| `privacy-manifest-sdk-data` | Collected data covers what linked SDKs (Firebase, AdMob, StoreKit, Sentry, …) collect, read from `pubspec.lock` | "Collects nothing" next to an analytics SDK — a label/manifest mismatch reviewers flag |
| `tracking-usage-description` | `NSUserTrackingUsageDescription` exists exactly when tracking is declared | App Store Connect refusing "Add for Review"; an ATT request that terminates the app |
| `purpose-string-missing` | Plugins that touch the camera, microphone, photos, location, contacts, Face ID… have their `NS…UsageDescription` | ITMS-90683 "Missing purpose string"; a crash at the first permission request |
| `purpose-string-quality` | Purpose strings name a feature and give an example instead of restating the permission | Guideline 5.1.1(ii) rejection ("needs camera access") |
| `background-modes-justified` | Every `UIBackgroundModes` entry is a known mode with a recorded justification or a plugin that uses it | Guideline 2.5.4 rejection ("unable to locate any features that require persistent audio") |
| `export-options-build-number` | `ExportOptions.plist` sets `manageAppVersionAndBuildNumber` to false | Xcode silently bumping `CFBundleVersion` at export |
| `bundle-localizations` | `CFBundleLocalizations` matches your ARB locales | Store listing and system prompts stuck in one language, or a listing that claims a language you don't ship |
| `push-entitlement` | Apps using push (FCM, OneSignal, `remote-notification`) carry `aps-environment` | Notifications that never arrive, with nothing failing |
| `android-picker-queries` | `file_picker` apps declare an `OPEN_DOCUMENT` `<queries>` intent | A file picker that never opens on some Android ROMs |
| `android-target-sdk` | `targetSdk` meets Google Play's current deadline (dated table, overridable; follows `flutter.targetSdkVersion` into your Flutter SDK) | Play Console refusing your update — usually during an urgent fix |
| `android-16kb-page-size` | Android Gradle Plugin ≥ 8.5.1 (or legacy packaging), NDK r28+ for your own native code | Play rejecting bundles without 16 KB page-size support |
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
```

**Exit codes:** `0` no finding at or above `--fail-on`; `1` at least one;
`2` usage error, invalid configuration, or not a Flutter project.

Paths in every output format are relative to the working directory, so in a
monorepo run it from the repository root with `--project apps/my_app` and the
paths (and SARIF annotations) point at the right files.

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
      - run: dart pub global activate imaji_store_preflight 0.1.0
      - run: dart pub global run imaji_store_preflight --sarif --output preflight.sarif
      - uses: github/codeql-action/upload-sarif@v3
        if: always()           # upload even when the check fails the job
        with:
          sarif_file: preflight.sarif
          category: imaji-store-preflight
```

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

## FAQ

**Does it need macOS or Xcode?** No. It reads files; it never builds. Run it on
Linux runners, in a pre-commit hook, anywhere Dart runs.

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
[android-16kb-check](https://github.com/saimskywalker/android-16kb-check).

## Support

If this saved you a review cycle, a ⭐ on the repository helps other Flutter
developers find it. Sponsorship through GitHub Sponsors keeps the rule tables
current with Apple's and Google's changes.

## License

MIT © saimskywalker. See [LICENSE](LICENSE).
