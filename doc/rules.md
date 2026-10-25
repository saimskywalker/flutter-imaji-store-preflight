# Rules

`imaji_store_preflight --list-rules` prints the rule list and
`imaji_store_preflight --explain <rule-id>` prints the full why, fix, options
and documentation links for one rule.

## Problems this solves

If you got one of these, this is the rule that catches it before upload.
Planned rules link the issue that tracks them.

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

## All rules

| Rule | Checks | Prevents |
|---|---|---|
| `privacy-manifest-present` | `PrivacyInfo.xcprivacy` exists (warning) and is in Copy Bundle Resources (error) | ITMS-91053 at upload when the app's own code uses a required-reason API; a manifest that never reaches the bundle |
| `privacy-manifest-values` | Data types, purposes, required-reason API categories and reason codes are Apple's exact values | A misspelt type that silently declares nothing; ITMS-91053 for an unapproved reason |
| `privacy-manifest-tracking` | `NSPrivacyTracking` agrees with each entry's Tracking flag and with `NSPrivacyTrackingDomains` | A manifest that contradicts itself and the privacy label |
| `privacy-manifest-sdk-data` | Collected data covers what linked SDKs (Firebase, AdMob, StoreKit, Sentry, …) collect, read from `pubspec.lock` | "Collects nothing" next to an analytics SDK, a label/manifest mismatch reviewers flag |
| `tracking-usage-description` | `NSUserTrackingUsageDescription` exists exactly when `PrivacyInfo.xcprivacy` declares tracking; warns when `app_tracking_transparency` is linked without it | App Store Connect refusing "Add for Review"; an ATT request that terminates the app |
| `purpose-string-missing` | Plugins that touch the camera, microphone, photos, location, contacts, Face ID… have their `NS…UsageDescription`; Always location also has When-In-Use | ITMS-90683 "Missing purpose string"; a crash at the first permission request |
| `purpose-string-quality` | Purpose strings name a feature and give an example instead of restating the permission | Guideline 5.1.1(ii) rejection ("needs camera access") |
| `background-modes-justified` | Every `UIBackgroundModes` entry is a mode Apple defines and has a justification recorded under `allow`: an error when no linked plugin uses the mode, a warning when one plausibly does; `processing` also needs `BGTaskSchedulerPermittedIdentifiers` | Guideline 2.5.4 rejection ("unable to locate any features that require persistent audio") |
| `export-options-build-number` | Every `ExportOptions*.plist` with method `app-store` / `app-store-connect` sets `manageAppVersionAndBuildNumber` to false (it defaults to YES) | Xcode silently bumping `CFBundleVersion` at export |
| `bundle-localizations` | `CFBundleLocalizations` matches your ARB locales | Store listing and system prompts stuck in one language, or a listing that claims a language you don't ship |
| `push-entitlement` | Apps using push (FCM, OneSignal, Airship, `remote-notification`) carry `aps-environment`, set to `development` or `production` | Notifications that never arrive, with nothing failing |
| `android-picker-queries` | `file_picker` apps declare an `OPEN_DOCUMENT` `<queries>` intent | A file picker that never opens on some Android ROMs |
| `android-target-sdk` | `targetSdk` meets Google Play's current deadline (dated table, overridable; follows `flutter.targetSdkVersion` into your Flutter SDK) | Play Console refusing your update, usually during an urgent fix |
| `android-16kb-page-size` | When `targetSdk` is 35+ or cannot be determined: Android Gradle Plugin ≥ 8.5.1 (or legacy packaging), NDK r28+ for your own native code | Play not letting you release an update without 16 KB page-size support, from 1 February 2027 ([Android guide](https://developer.android.com/guide/practices/page-sizes#google-play-compatibility-requirement)) |
| `unreadable-file` | Every file above parses (binary plists get a `plutil` hint) | Rules silently passing a file nobody could read |

## What a finding looks like

Without `--brief`, every rule also says
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
