# imaji_store_preflight

> Status: **pre-alpha, not published.** Progress is tracked in the issues.

The App Store and Google Play reject builds for configuration contradictions
that compile cleanly and pass every test. `imaji_store_preflight` reads your
`Info.plist`, privacy manifest, entitlements, `ExportOptions.plist` and
`AndroidManifest.xml`, and fails CI on the contradictions reviewers look for.

Every rule says **why it matters** — which rejection or silent failure it
prevents — not just what is wrong.

## Example rules

| Rule | What it prevents |
|---|---|
| `PrivacyInfo.xcprivacy` declares no collected data while an analytics SDK is linked | A privacy label that disagrees with the manifest |
| `NSUserTrackingUsageDescription` present while `NSPrivacyTracking` is false | App Store Connect refusing "Add for Review" |
| A data type or purpose that is not one of Apple's defined values | Manifest silently ignored |
| `UIBackgroundModes` entry with no feature behind it | Guideline 2.5.4 rejection |
| A purpose string that only restates the permission ("needs camera access") | Guideline 5.1.1 rejection |
| `ExportOptions.plist` with `manageAppVersionAndBuildNumber = true` | Xcode silently bumping the build number at export |
| `FileType.custom` picking without an `OPEN_DOCUMENT` `<queries>` entry | A file picker that never opens on some Android ROMs |
| `CFBundleLocalizations` missing a locale your ARB files ship | Store listing and system UI in the wrong language |

## Planned usage

```bash
dart run imaji_store_preflight            # reads ios/ and android/ from the project root
dart run imaji_store_preflight --sarif    # GitHub code scanning output
```

## License

MIT. See [LICENSE](LICENSE).
