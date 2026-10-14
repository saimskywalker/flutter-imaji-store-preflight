# Changelog

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
