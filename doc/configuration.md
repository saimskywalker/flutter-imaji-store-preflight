# Command line and configuration

## Command line

```text
storehound [options] [project-dir]

-p, --project=<dir>     Flutter project root to check (default ".")
-c, --config=<file>     Configuration file (default: storehound.yaml in the project)
-f, --format            text (default), json, sarif
    --sarif             Shorthand for --format sarif
-o, --output=<file>     Write the report to a file; a one-line summary goes to stderr
    --fail-on           error (default), warning, info, never
    --today=YYYY-MM-DD  Date deadlines are measured against (reproducible runs)
    --brief             Text output without the why/fix explanations
    --[no-]color        Colour text output (default: when stdout is a terminal and NO_COLOR is unset)
    --list-rules        List every rule
    --explain=<rule-id> Explain one rule, or a project check as check:<name>
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

Optional. Put `storehound.yaml` next to `pubspec.yaml`:

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
  purpose-string-missing:
    linked_by_plugin:       # SDKs whose binary references an API the app never requests
      my_calling_plugin: [NSMotionUsageDescription]
  purpose-string-quality:
    min_words: 8
    app_names: [MyApp]
    extra_example_markers: ["like"]
    linked_only:            # keys only there for a referenced API, checked by hand
      NSMotionUsageDescription: "Referenced by the calling SDK; never requested."

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
| `purpose-string-missing` | `required_by_plugin` (package → Info.plist keys it requests), `linked_by_plugin` (package → Info.plist keys its binary only references) |
| `purpose-string-quality` | `min_words`, `require_example`, `app_names`, `extra_example_markers`, `extra_unused_markers`, `linked_only` (Info.plist key → why it is there) |
| `background-modes-justified` | `allow` (mode → justification), `extra_evidence` (mode → packages) |
| `android-picker-queries` | `plugins` (extra file-picker packages) |
| `android-target-sdk` | `target_sdk`, `deadlines` (`api`, `from`), `warn_days` |

## Project checks

Pins that only your app cares about, the kind usually kept as hand-written
tests that parse `Info.plist` or `AndroidManifest.xml`, go under `checks:`.
Each one is reported like a built-in rule, with the rule id `check:<name>`:

```yaml
checks:
  encryption-exempt:
    file: info_plist
    key: ITSAppUsesNonExemptEncryption
    equals: false
    reason: "Export compliance is answered in App Store Connect; keeps each upload from asking."

  background-modes-pinned:
    file: info_plist
    key: UIBackgroundModes
    equals: [audio, remote-notification]
    reason: "The modes App Review accepted. A new one needs review notes first."

  ats-no-arbitrary-loads:
    file: info_plist
    key: NSAppTransportSecurity.NSAllowsArbitraryLoads   # a dot steps into a nested dictionary
    absent_or_equals: false
    reason: "All traffic is HTTPS."

  no-backup:
    file: android_manifest
    element: application
    attribute: android:allowBackup
    equals: "false"
    severity: warning
    reason: "Tokens live in shared preferences."

  no-media-permissions:
    file: android_manifest
    element: uses-permission
    attribute: android:name
    none_of: [android.permission.READ_MEDIA_IMAGES, android.permission.READ_MEDIA_VIDEO]
    reason: "The app uses the system photo picker only."
```

| Key | Meaning |
|---|---|
| `file` | `info_plist` (`paths.info_plist`) or `android_manifest` (the main manifest, `paths.android_manifest`) |
| `key` | Info.plist only. A top-level key, or a dotted path into nested dictionaries. For a key that contains dots, list the parts: `[NSAppTransportSecurity, NSExceptionDomains, example.com]` |
| `element`, `attribute` | AndroidManifest only. Every element with that name, anywhere in the manifest, and the attribute's name as written, e.g. `android:allowBackup` |
| `reason` | Required: why the value is pinned. Shown as the "why" in every report and in `--explain` |
| `severity` | `error` (default), `warning` or `info` |

Each check has exactly one operator:

| Operator | Info.plist value | AndroidManifest attribute |
|---|---|---|
| `exists: true` | is present | at least one element sets it |
| `absent: true` | is not present | no element sets it |
| `equals: <value>` | is present and equal; a list equals an array with the same items in any order | every element sets it to the value |
| `absent_or_equals: <value>` | is missing or equal | every element that sets it uses the value |
| `not_equals: <value>` | is missing or different | no element sets it to the value |
| `contains: [<values>]` | is an array that holds every listed value | the elements' values together hold every listed value |
| `none_of: [<values>]` | is none of the values (for an array: no item is) | no element's value is listed |
| `matches: <regex>` | is a string the regular expression matches | every element sets a value it matches |

Values are compared with their type: `equals: false` matches `<false/>`, not
`<string>NO</string>`, and `equals: "42"` does not match `<integer>42</integer>`.
Manifest attributes are text, so quote values there (`equals: "false"`).
`matches` finds the pattern anywhere in the value; anchor it with `^` and `$`
to match the whole value.

Findings point at the value's line; when the value is missing, at its
parent: the enclosing dictionary's key in Info.plist, the element in the
manifest, or `<manifest>` when no element has that name. A check whose file
does not exist is a finding too, so a moved file cannot switch it off
silently. A check can be named in `ignore` (`rule: check:no-backup`) and under
`rules:` like any rule, and `storehound --explain check:no-backup` prints it.
Mistakes in a check (an unknown file or operator, a value of the wrong type,
a missing `reason`) are configuration errors with the line number, exit
code 2.

The privacy manifest and entitlements are not supported yet.

## Use it as a library

```dart
import 'package:storehound/storehound.dart';

void main() {
  final report = runPreflight('path/to/flutter_app');
  print(renderText(report));
}
```

`renderJson` (stable schema, `schemaVersion: 1`) and `renderSarif` are exported
too, and `Rule` is the extension point; see [CONTRIBUTING.md](https://github.com/saimskywalker/storehound/blob/main/CONTRIBUTING.md).

