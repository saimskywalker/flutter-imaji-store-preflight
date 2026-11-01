# Test fixtures

Every fixture is invented for this repository: no real app, company, bundle
id, hostname, key or person. Hostnames use `example.com` / `example.net`,
bundle and application ids use `com.example.*`, and Firebase files hold
placeholder values.

| Fixture | Shape | Expected result |
|---|---|---|
| `clean_app` | Minimal, like `flutter create` output | No findings |
| `rejected_app` | Minimal, with one mistake per rule | Findings from most rules (see `test/cli_test.dart`) |
| `production_app` | A multi-flavor app shaped like one in production (below) | No findings with `--fail-on info`; output in `production_app.golden.txt` |

## production_app

`acme_shop`, a shopping app with barcode scanning, Face ID checkout, audio
guides and order-status pushes. It exists to show that a correctly configured
production app passes with no findings at all, and
`test/production_app_test.dart` changes one thing at a time in a copy of it to
show that each mistake is still caught.

What it covers:

- **Debug and Release entitlements side by side.**
  `ios/Runner/RunnerDebug.entitlements` and `RunnerRelease.entitlements`, each
  named by `CODE_SIGN_ENTITLEMENTS` in `project.pbxproj` (Profile signs with
  the Release file), both with `aps-environment` and associated domains.
- **Honest purpose strings for linked-but-unused APIs.** Both location keys
  say the app does not use location and why the key is present; the
  reference is recorded under `purpose-string-missing` -> `linked_by_plugin`
  for the path package `acme_payments`.
- **Flavors that share one applicationId.** `dev` and `prod` in
  `android/app/build.gradle.kts` differ only in `src/<flavor>/res` and
  `src/<flavor>/google-services.json`.
- **iOS flavors done by a build script.** No per-flavor Xcode
  configurations: `ios/scripts/select_flavor.sh` reads `FLAVOR` from
  `DART_DEFINES` and copies `ios/config/<flavor>/` into place.
- **SwiftPM only.** No `Podfile` or `Podfile.lock`; the Xcode project links
  `FlutterGeneratedPluginSwiftPackage`.
- **AGP 9 with built-in Kotlin.** The AGP version is only in
  `settings.gradle.kts`, there is no Kotlin Android plugin, the app module
  has a top-level `kotlin { compilerOptions { … } }` block and no
  `kotlinOptions`, `compileSdk` (37) is above `targetSdk` (36), `ndkVersion`
  is pinned, and an old `targetSdk` line is left commented out.
- **A large, heavily commented `Info.plist`.** Comments before the root
  element, inside `<array>` and `<dict>` and between a key and its value; 240
  `SKAdNetworkItems`; `$(VARIABLE)` values (including the display name); a
  scene manifest.
- **`src/debug` and `src/profile` manifest overlays** that add `INTERNET`
  only for development.
- **Deliberately absent permissions.** No `READ_MEDIA_*` or storage
  permission (files come through the system document picker), with
  `<queries>` entries for both `OPEN_DOCUMENT` and `GET_CONTENT`.
- **A bundled `PrivacyInfo.xcprivacy`** declaring what Firebase Analytics,
  Crashlytics and Messaging collect, plus four required-reason APIs.
- **Two ARB locales** (`en`, `pt_BR`) under `lib/l10n/arb` (set in
  `l10n.yaml`), listed in `CFBundleLocalizations` as `en` and `pt-BR`.
- **`audio` and `remote-notification` background modes**, each justified
  under `background-modes-justified` -> `allow`.
- **Multiple App Links hosts** on one `autoVerify` intent filter, matching
  the `applinks:` associated domains.
- **Two ExportOptions files**: App Store Connect (build number managed by
  CI) and ad hoc (`release-testing`).

Not covered yet, because no rule reads these files: per-flavor and
per-build-type Android manifests beyond `src/main`, per-flavor Info.plist or
privacy manifests, and app extensions (see issue #15).

When a rule or its output changes, regenerate the golden file from the
repository root:

```bash
dart run imaji_store_preflight --project test/fixtures/production_app \
  --fail-on info --today 2026-10-01 --brief --no-color \
  > test/fixtures/production_app.golden.txt
```

A new finding on this fixture is a false positive until shown otherwise: fix
the rule, or explain in the pull request why the fixture is wrong.
