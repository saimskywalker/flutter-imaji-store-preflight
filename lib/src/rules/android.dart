import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/play_target_sdk.dart';
import '../finding.dart';
import '../project.dart';
import '../rule.dart';

/// The app declares the `<queries>` its file picker resolves against.
class AndroidPickerQueriesRule extends Rule {
  /// Creates the rule.
  const AndroidPickerQueriesRule();

  @override
  String get id => 'android-picker-queries';

  @override
  String get title =>
      'File pickers have an OPEN_DOCUMENT <queries> entry in the manifest';

  @override
  RulePlatform get platform => RulePlatform.android;

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  String get why =>
      'Since Android 11, `resolveActivity` only sees packages the app has '
      'declared visibility of. `file_picker` checks that call before '
      'launching, and for `FileType.any` and `FileType.custom` it launches '
      '`ACTION_OPEN_DOCUMENT` — while its own manifest only declares '
      '`GET_CONTENT`. On ROMs whose documents provider is not automatically '
      'visible the picker never opens and the plugin reports that no file '
      'manager exists. It builds, it passes every emulator test, and it is a '
      'permanent failure on the affected devices. Adding a storage permission '
      'does not help: no file was ever read.';

  @override
  String get fix =>
      'Add to AndroidManifest.xml, as a child of <manifest>:\n'
      '  <queries>\n'
      '    <intent>\n'
      '      <action android:name="android.intent.action.OPEN_DOCUMENT" />\n'
      '      <category android:name="android.intent.category.OPENABLE" />\n'
      '      <data android:mimeType="*/*" />\n'
      '    </intent>\n'
      '  </queries>\n'
      'Keep the mimeType `*/*`: the extension filter travels in an extra that '
      'intent resolution never reads.';

  @override
  List<String> get docs => const [
    'https://developer.android.com/training/package-visibility',
    'https://developer.android.com/training/package-visibility/declaring',
    'https://developer.android.com/reference/android/content/Intent#ACTION_OPEN_DOCUMENT',
  ];

  @override
  Set<String> get optionKeys => const {'plugins'};

  @override
  String? validateOptions(Map<String, Object?> options) =>
      OptionChecks.stringList('plugins', options['plugins']);

  static const _action = 'android.intent.action.OPEN_DOCUMENT';

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final project = context.project;
    final manifest = project.androidManifest;
    if (manifest == null) return;
    final plugins = [
      'file_picker',
      ...(context.options['plugins'] as List? ?? const []).cast<String>(),
    ].where(project.links).toList();
    if (plugins.isEmpty) return;
    final queries = manifest.root.elements('queries').toList();
    final intents = [
      for (final q in queries)
        for (final intent in q.elements('intent'))
          if (intent
              .elements('action')
              .any((a) => a.attributes['android:name'] == _action))
            intent,
    ];
    if (intents.isEmpty) {
      yield finding(
        '${plugins.join(', ')} ${plugins.length == 1 ? 'is' : 'are'} linked, '
        'but no <queries> <intent> declares `$_action`.',
        path: manifest.path,
        line: queries.isEmpty ? manifest.root.line : queries.first.line,
      );
      return;
    }
    final typed = intents.any(
      (i) => i
          .elements('data')
          .any((d) => d.attributes.containsKey('android:mimeType')),
    );
    if (!typed) {
      yield finding(
        'The `$_action` query has no <data android:mimeType="*/*"/>, so it '
        'does not match the typed intent the picker sends.',
        path: manifest.path,
        line: intents.first.line,
        severity: Severity.warning,
      );
    }
  }
}

/// A resolved `targetSdk` and where it came from.
class ResolvedTargetSdk {
  /// Creates a resolution result.
  const ResolvedTargetSdk(this.value, this.source, {this.path, this.line});

  /// The API level, or `null` when it could not be determined.
  final int? value;

  /// Human-readable description of where [value] came from, or why not.
  final String source;

  /// The file the declaration is in.
  final String? path;

  /// The line of the declaration.
  final int? line;
}

final _literalTarget = RegExp(
  r'targetSdk(?:Version)?\s*(?:=\s*|\(\s*|\s+)(\d+)',
);
final _flutterTarget = RegExp(
  r'targetSdk(?:Version)?\s*(?:=\s*|\(\s*|\s+)flutter\.targetSdkVersion',
);
final _flutterDefault = RegExp(r'targetSdkVersion\s*(?::\s*Int\s*)?=\s*(\d+)');

/// Works out the app's `targetSdk` from its Gradle script, following
/// `flutter.targetSdkVersion` into the Flutter SDK when it can.
ResolvedTargetSdk resolveTargetSdk(Project project) {
  final gradle = project.appGradle;
  if (gradle == null) {
    return const ResolvedTargetSdk(null, 'no android/app Gradle script');
  }
  final literal = _literalTarget.firstMatch(gradle.text);
  if (literal != null) {
    return ResolvedTargetSdk(
      int.parse(literal.group(1)!),
      gradle.path,
      path: gradle.path,
      line: gradle.lineOf(literal),
    );
  }
  final viaFlutter = _flutterTarget.firstMatch(gradle.text);
  if (viaFlutter == null) {
    return ResolvedTargetSdk(
      null,
      'no targetSdk declaration found in ${gradle.path}',
      path: gradle.path,
    );
  }
  final line = gradle.lineOf(viaFlutter);
  final root = project.flutterRoot;
  if (root != null) {
    for (final candidate in const [
      'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt',
      'packages/flutter_tools/gradle/src/main/groovy/flutter.groovy',
    ]) {
      final file = File(p.join(root, candidate));
      if (!file.existsSync()) continue;
      final match = _flutterDefault.firstMatch(file.readAsStringSync());
      if (match != null) {
        return ResolvedTargetSdk(
          int.parse(match.group(1)!),
          'flutter.targetSdkVersion from the Flutter SDK at $root',
          path: gradle.path,
          line: line,
        );
      }
    }
  }
  return ResolvedTargetSdk(
    null,
    '${gradle.path} uses flutter.targetSdkVersion and the Flutter SDK could '
    'not be located (run `flutter pub get` or set FLUTTER_ROOT)',
    path: gradle.path,
    line: line,
  );
}

/// `targetSdk` meets Google Play's current requirement.
class AndroidTargetSdkRule extends Rule {
  /// Creates the rule.
  const AndroidTargetSdkRule();

  @override
  String get id => 'android-target-sdk';

  @override
  String get title => "targetSdk meets Google Play's current deadline";

  @override
  RulePlatform get platform => RulePlatform.android;

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  String get why =>
      'Each year Google Play raises the minimum target API level for new apps '
      'and app updates. After the deadline the Play Console refuses to '
      'publish an update that targets an older level — usually discovered '
      'during an urgent fix, when the target bump (with its behaviour '
      'changes) is the last thing anyone wants to ship.';

  @override
  String get fix =>
      'Raise `targetSdk` in android/app/build.gradle(.kts), or upgrade '
      'Flutter if it comes from `flutter.targetSdkVersion`, and test the '
      "behaviour changes listed for that API level. Use this rule's "
      '`deadlines` option to add a newly announced deadline or an extension '
      'Google granted you, `warn_days` to change how early you are warned, '
      'and `target_sdk` to state the value when it cannot be detected.';

  @override
  List<String> get docs => const [
    'https://developer.android.com/google/play/requirements/target-sdk',
    'https://support.google.com/googleplay/android-developer/answer/11926878',
  ];

  @override
  Set<String> get optionKeys => const {'target_sdk', 'deadlines', 'warn_days'};

  @override
  String? validateOptions(Map<String, Object?> options) {
    if (options.containsKey('target_sdk') && options['target_sdk'] is! int) {
      return '`target_sdk` must be an integer API level';
    }
    if (options.containsKey('warn_days')) {
      final days = options['warn_days'];
      if (days is! int || days < 0) {
        return '`warn_days` must be a non-negative integer';
      }
    }
    if (options.containsKey('deadlines')) {
      final rows = options['deadlines'];
      if (rows is! List) return '`deadlines` must be a list';
      for (final row in rows) {
        if (row is! Map ||
            row['api'] is! int ||
            row['from'] == null ||
            DateTime.tryParse('${row['from']}') == null) {
          return 'each `deadlines` entry needs `api` (integer) and `from` '
              '(YYYY-MM-DD)';
        }
      }
    }
    return null;
  }

  /// The effective deadline table for [options], oldest first.
  static List<TargetSdkDeadline> deadlines(Map<String, Object?> options) {
    final byApi = {for (final d in builtInTargetSdkDeadlines) d.apiLevel: d};
    for (final row
        in (options['deadlines'] as List? ?? const [])
            .cast<Map<Object?, Object?>>()) {
      final api = row['api'] as int;
      final from = DateTime.parse('${row['from']}');
      byApi[api] = TargetSdkDeadline(
        api,
        DateTime.utc(from.year, from.month, from.day),
      );
    }
    return byApi.values.toList()..sort((a, b) => a.from.compareTo(b.from));
  }

  static String _date(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final project = context.project;
    if (project.appGradle == null && project.androidManifest == null) return;
    final override = context.options['target_sdk'] as int?;
    final resolved = override != null
        ? ResolvedTargetSdk(override, 'the `target_sdk` option')
        : resolveTargetSdk(project);
    final target = resolved.value;
    if (target == null) {
      yield finding(
        'Could not determine targetSdk: ${resolved.source}. Set the '
        '`target_sdk` option to check it against the Play deadline.',
        path: resolved.path,
        line: resolved.line,
        severity: Severity.info,
      );
      return;
    }
    final today = context.today;
    final table = deadlines(context.options);
    TargetSdkDeadline? current;
    TargetSdkDeadline? next;
    for (final row in table) {
      if (!row.from.isAfter(today)) {
        if (current == null || row.apiLevel > current.apiLevel) current = row;
      } else {
        next ??= row;
      }
    }
    if (current != null && target < current.apiLevel) {
      yield finding(
        'targetSdk is $target (${resolved.source}), but since '
        '${_date(current.from)} Google Play requires at least '
        '${current.apiLevel} for new apps and updates.',
        path: resolved.path,
        line: resolved.line,
      );
      return;
    }
    final warnDays = context.options['warn_days'] as int? ?? 120;
    if (next != null &&
        target < next.apiLevel &&
        next.from.difference(today).inDays <= warnDays) {
      yield finding(
        'targetSdk is $target; from ${_date(next.from)} '
        '(${next.from.difference(today).inDays} days) Google Play requires '
        '${next.apiLevel}.',
        path: resolved.path,
        line: resolved.line,
        severity: Severity.warning,
      );
    }
  }
}

/// The Android build packages native libraries for 16 KB memory pages.
class Android16KbPageSizeRule extends Rule {
  /// Creates the rule.
  const Android16KbPageSizeRule();

  @override
  String get id => 'android-16kb-page-size';

  @override
  String get title => 'The build toolchain supports 16 KB page sizes';

  @override
  RulePlatform get platform => RulePlatform.android;

  @override
  Severity get defaultSeverity => Severity.warning;

  // Policy text follows the "Google Play compatibility requirement" section of
  // https://developer.android.com/guide/practices/page-sizes (last updated
  // 2026-09-16) and the announcement at
  // https://android-developers.googleblog.com/2025/05/prepare-play-apps-for-devices-with-16kb-page-size.html.
  // The AGP 8.5.1 and NDK r28 thresholds come from the same guide's "Update
  // the packaging of your shared libraries" and "Compile your app using 16 KB
  // ELF alignment" sections.
  @override
  String get why =>
      'Google Play requires apps that target Android 15 (API level 35) or '
      'higher to support 16 KB memory page sizes on 64-bit devices; the '
      'requirement was announced for new apps and updates submitted from '
      '1 November 2025, and from 1 February 2027 an app update without '
      '16 KB support cannot be released. Uncompressed native libraries must '
      'be 16 KB zip-aligned in the APK/AAB, which needs Android Gradle Plugin '
      '8.5.1 or later; with older versions an app built from a bundle in '
      'Play may not install on 16 KB devices.';

  @override
  String get fix =>
      'Upgrade the Android Gradle Plugin to 8.5.1 or later (in '
      'android/settings.gradle(.kts)); if that is impossible, set '
      '`packaging.jniLibs.useLegacyPackaging = true` (on AGP 8.0 or older, '
      'also `android.bundle.enableUncompressedNativeLibs = false` in '
      'android/gradle.properties). Projects with their own '
      'C/C++ code also need NDK r28+ (or the 16 KB linker flag). Source '
      'checks cannot see prebuilt `.so` files inside plugins: verify the '
      'built bundle with an ELF alignment check such as '
      'https://github.com/saimskywalker/android-imaji-16kb-alignment or the '
      '`check_elf_alignment.sh` script from the Android documentation.';

  @override
  List<String> get docs => const [
    'https://developer.android.com/guide/practices/page-sizes#google-play-compatibility-requirement',
    'https://android-developers.googleblog.com/2025/05/prepare-play-apps-for-devices-with-16kb-page-size.html',
  ];

  static final _pluginsDsl = RegExp(
    r'''com\.android\.application["']?\s*\)?\s+version\s+["']([\d.]+)["']''',
  );
  static final _classpath = RegExp(
    r'''com\.android\.tools\.build:gradle:([\d.]+)''',
  );
  static final _legacyPackaging = RegExp(r'useLegacyPackaging\s*(?:=\s*)?true');
  static final _ndk = RegExp(r'''ndkVersion\s*(?:=\s*)?["'](\d+)\.''');

  static bool _older(String version, List<int> than) {
    final parts = version.split('.').map(int.tryParse).toList();
    for (var i = 0; i < than.length; i++) {
      final v = i < parts.length ? (parts[i] ?? 0) : 0;
      if (v != than[i]) return v < than[i];
    }
    return false;
  }

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final project = context.project;
    final app = project.appGradle;
    if (app == null) return;
    final target = resolveTargetSdk(project).value;
    if (target != null && target < 35) return;

    TextFile? agpFile;
    Match? agp;
    for (final (file, pattern) in [
      (project.settingsGradle, _pluginsDsl),
      (project.rootGradle, _classpath),
    ]) {
      final match = file == null ? null : pattern.firstMatch(file.text);
      if (match != null) {
        agpFile = file;
        agp = match;
        break;
      }
    }
    if (agp != null &&
        _older(agp.group(1)!, const [8, 5, 1]) &&
        !_legacyPackaging.hasMatch(app.text)) {
      yield finding(
        'Android Gradle Plugin ${agp.group(1)} is older than 8.5.1, the '
        'version needed to 16 KB zip-align uncompressed native libraries.',
        path: agpFile!.path,
        line: agpFile.lineOf(agp),
      );
    }
    final ndk = _ndk.firstMatch(app.text);
    if (ndk != null &&
        int.parse(ndk.group(1)!) < 28 &&
        app.text.contains('externalNativeBuild')) {
      yield finding(
        'NDK ${ndk.group(1)} does not produce 16 KB-aligned libraries by '
        'default, and this module builds its own native code.',
        path: app.path,
        line: app.lineOf(ndk),
      );
    }
  }
}
