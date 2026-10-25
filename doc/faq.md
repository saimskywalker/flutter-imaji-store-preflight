# FAQ, limitations and comparisons

## How it compares

It complements the checks you already have; it does not replace them.

- **Upload processing in App Store Connect / Xcode "Validate App"** is the
  authority on `ITMS-` errors, but needs macOS, a signed archive and a
  finished build. It does not judge purpose-string wording or look at
  Android.
- **[fastlane precheck](https://docs.fastlane.tools/actions/precheck/)**
  checks your App Store *metadata* (description, keywords, URLs) for
  rejection-prone text. `imaji_store_preflight` checks the *configuration
  files in your project*, so the two do not overlap.
- **Google Play Console** tells you about target API level and 16 KB
  page-size problems when you upload a bundle. This tool tells you on the pull
  request that introduces them.

## FAQ and limitations

**Does it need macOS or Xcode?** No. It reads files; it never builds. Run it on
Linux runners, in a pre-commit hook, anywhere Dart runs.

**Will it find every reason for a rejection?** No. It finds contradictions and
omissions in the configuration files listed above. It does not see your
app's behaviour, your store listing or your binary. Treat a clean run as
"none of these known mistakes", not as an approval.

**Does it read my dependencies' own privacy manifests or scan native code for
required-reason APIs?** Not yet. It reads `pubspec.lock` to know which
plugins are linked; checking their manifests and native code is planned in
[#13](https://github.com/saimskywalker/flutter-imaji-store-preflight/issues/13)
and
[#17](https://github.com/saimskywalker/flutter-imaji-store-preflight/issues/17).

**Flavors, app extensions, monorepos?** Each run checks one `Info.plist`, one
privacy manifest and one `AndroidManifest.xml` (configurable under `paths`).
Use `--project` for each app in a monorepo; checking every flavor and
extension in one run is planned in
[#15](https://github.com/saimskywalker/flutter-imaji-store-preflight/issues/15).

**My Info.plist is a binary plist.** Xcode reads both formats; this tool reads
XML and says so clearly. Convert once with `plutil -convert xml1 Info.plist`;
XML is also what makes the file reviewable in a diff.

**A heuristic is wrong for my app.** Add an `ignore` entry with the reason, or
tune the rule's options. If the heuristic is wrong in general, please open an
issue with an anonymised example; the purpose-string and SDK tables get
better with real cases.

**Why does turning a rule off need a reason?** Because the next person to read
the config will want to turn it back on, and a reason is the only thing that
tells them whether that is safe.

**Apple added a new data type / Google moved a deadline.** Use
`extra_data_types` / `deadlines` until a release catches up, and open an issue.
The tables cite the documentation they came from.

**Does it check localized `InfoPlist.strings` purpose strings?** Not yet; only
the base `Info.plist` values.

**Does `privacy-manifest-sdk-data` know every SDK?** No. It knows common
Flutter plugins and is deliberately conservative (a type is listed only when
the SDK collects it by default). Extend it with `sdk_data_types`.

**Is 16 KB alignment fully checked?** Only the build toolchain, from source.
Prebuilt `.so` files inside plugins can only be checked in the built APK/AAB;
use an ELF alignment check such as
[android-imaji-16kb-alignment](https://github.com/saimskywalker/android-imaji-16kb-alignment).
