# GitHub Actions

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
Security), drop the upload step and use the default text output; the job log
then carries the why/fix for every finding. Suppressed findings are written to
the SARIF with their reason, so code scanning shows them as dismissed.
