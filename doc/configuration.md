# Command line and configuration

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

## Use it as a library

```dart
import 'package:imaji_store_preflight/imaji_store_preflight.dart';

void main() {
  final report = runPreflight('path/to/flutter_app');
  print(renderText(report));
}
```

`renderJson` (stable schema, `schemaVersion: 1`) and `renderSarif` are exported
too, and `Rule` is the extension point; see [CONTRIBUTING.md](https://github.com/saimskywalker/flutter-imaji-store-preflight/blob/main/CONTRIBUTING.md).

