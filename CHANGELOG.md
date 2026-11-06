# Changelog

## 0.3.0

- Project checks: app-specific pins under `checks:` in `storehound.yaml`, for
  `Info.plist` keys (with nested keys) and `AndroidManifest.xml` attributes,
  with the operators `exists`, `absent`, `equals`, `absent_or_equals`,
  `not_equals`, `contains`, `none_of` and `matches`. Each check needs a
  `reason`, defaults to `error`, and is reported in text, JSON and SARIF as
  `check:<name>` with the file and line of the value (or of its parent when
  it is missing). `ignore`, `rules` and `--explain check:<name>` accept it.
  A mistake in a check is a configuration error with its line (exit code 2).
- The production-shaped fixture pins five values with `checks:`.

## 0.2.0

Renamed from imaji_store_preflight. Same rules and CLI; the command is now
`storehound`.

- The configuration file is `storehound.yaml`. An existing
  `imaji_store_preflight.yaml` is still read when `storehound.yaml` is absent,
  with a note to rename it.
- `dart pub global activate storehound` also installs an
  `imaji_store_preflight` command for this release only; it will be removed
  in the next minor release.
- The library import is `package:storehound/storehound.dart`.
- Reports name the tool `storehound`: the text summary, JSON `tool.name`, and
  the SARIF driver `name` and `informationUri`.
- `push-entitlement` reads `CODE_SIGN_ENTITLEMENTS` from the Xcode project
  when Debug and Release sign with different entitlements files: a Release
  file without `aps-environment` is reported even when the Debug file has
  it, and so is a project where only Debug configurations sign with
  entitlements.
- `android-target-sdk` and `android-16kb-page-size` ignore commented-out
  lines in Gradle scripts, so `// targetSdk = 34` above the real value is no
  longer reported.
- A production-shaped test fixture (flavors, SwiftPM only, AGP 9, Debug and
  Release entitlements, a large commented `Info.plist`) that CI checks with
  `--fail-on info`.
- `purpose-string-missing` reports keys for protected APIs that a bundled
  native SDK only references (ITMS-90683 is a static check), listed with the
  new `linked_by_plugin` option or the new `linkedApiReferences` table (empty
  until a row has binary evidence). A CoreLocation reference asks for both
  `NSLocationWhenInUseUsageDescription` and
  `NSLocationAlwaysAndWhenInUseUsageDescription`.
- `purpose-string-quality` accepts an honest "not used" string (says the app
  does not use the resource and why the key is present) without an example,
  recognised by its wording (`extra_unused_markers` adds phrases) or listed
  under the new `linked_only` option. Such a string is an error while a plugin
  that requests the permission is a direct dependency, and a warning when that
  plugin is transitive. "Not used." on its own is still an error.

## 0.1.2

- pubspec description mentions entitlements and CI.
- README: a GitHub Actions job with SARIF upload and the exit codes, so the
  CI setup is on the pub.dev page; the Actions example uses
  `actions/checkout@v6` and `github/codeql-action/upload-sarif@v4`.

## 0.1.1

Documentation and rule text only; no rule logic or CLI behaviour changes.

- `android-16kb-page-size` states Google Play's 16 KB requirement as the
  Android page-sizes guide now does: apps targeting Android 15 (API level 35)
  or higher must support 16 KB pages on 64-bit devices, and from
  1 February 2027 an update without that support cannot be released. The old
  text said bundles have been refused at upload since 1 November 2025; that
  date is the requirement's announced start, not a release block. The rule's
  docs link now points at the guide's "Google Play compatibility requirement"
  section and the announcement post; the AGP finding no longer claims older
  versions align to 4 KB, and the fix adds the AGP 8.0-and-older
  `android.bundle.enableUncompressedNativeLibs = false` step from the guide.

- README: pub.dev version and pub points badges; install pinned to
  `^0.1.0`; the GitHub Actions example activates `^0.1.0` and explains that a
  Dart-only runner cannot resolve `flutter.targetSdkVersion`.
- README rule table corrected against the code: `background-modes-justified`
  wants an `allow` justification for every mode (a linked plugin only lowers
  the finding to a warning); `export-options-build-number` checks App Store
  Connect export methods only; `android-16kb-page-size` is skipped below
  `targetSdk` 35; `privacy-manifest-present`,
  `tracking-usage-description`, `purpose-string-missing` and
  `push-entitlement` list what they actually check.
- README command line: `--version` and `--help` listed, every exit-code `2`
  case named, and the example summary line matches a real run.
- CONTRIBUTING: the CI commands listed as CI runs them.

## 0.1.0

First release.

- Rules engine with per-rule enable/disable (a reason is required), severity
  overrides, rule options and `ignore` entries (a reason is required);
  configuration in `imaji_store_preflight.yaml`, validated with line numbers.
- Text (with why/fix per rule), JSON (`schemaVersion: 1`) and SARIF 2.1.0
  output; exit codes 0 / 1 / 2; `--fail-on`, `--today`, `--list-rules`,
  `--explain`.
- XML property list reader with line tracking; binary plists are refused with
  a `plutil` conversion hint.
- iOS rules: `privacy-manifest-present`, `privacy-manifest-values`,
  `privacy-manifest-tracking`, `privacy-manifest-sdk-data`,
  `tracking-usage-description`, `purpose-string-missing`,
  `purpose-string-quality`, `background-modes-justified`,
  `export-options-build-number`, `bundle-localizations`, `push-entitlement`.
- Android rules: `android-picker-queries`, `android-target-sdk` (dated Play
  deadline table, follows `flutter.targetSdkVersion` into the Flutter SDK),
  `android-16kb-page-size`.
- `unreadable-file` for configuration files that cannot be parsed.
