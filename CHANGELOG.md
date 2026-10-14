# Changelog

## 0.1.1

Documentation only; no rule or CLI behaviour changes.

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
