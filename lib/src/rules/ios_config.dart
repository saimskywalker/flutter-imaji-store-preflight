import '../data/apple_privacy.dart';
import '../data/plugin_requirements.dart';
import '../finding.dart';
import '../rule.dart';

/// Every `UIBackgroundModes` entry has a feature a reviewer can find.
class BackgroundModesRule extends Rule {
  /// Creates the rule.
  const BackgroundModesRule();

  @override
  String get id => 'background-modes-justified';

  @override
  String get title => 'Every UIBackgroundModes entry is justified';

  @override
  RulePlatform get platform => RulePlatform.ios;

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  String get why =>
      'App Review treats each `UIBackgroundModes` entry as a claim and checks '
      'them one by one (Guideline 2.5.4). The typical rejection reads "the app '
      'declares support for audio in the UIBackgroundModes key but we are '
      'unable to locate any features that require persistent audio" — and it '
      'happens even when the feature exists, if the reviewer cannot reach it. '
      'Modes left over from a template or a removed plugin are pure risk.';

  @override
  String get fix =>
      'Remove modes nothing uses. For each mode you keep, record how a '
      'reviewer reaches the feature under this rule\'s `allow` option (mode to '
      'justification) and say the same in the App Review notes; if the app '
      'refuses the feature in some states (screen capture, logged out), say '
      'so too. `processing` also needs `BGTaskSchedulerPermittedIdentifiers`.';

  @override
  List<String> get docs => const [
    'https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes',
    'https://developer.apple.com/app-store/review/guidelines/#2.5.4',
    'https://developer.apple.com/documentation/bundleresources/information-property-list/bgtaskschedulerpermittedidentifiers',
  ];

  @override
  Set<String> get optionKeys => const {'allow', 'extra_evidence'};

  @override
  String? validateOptions(Map<String, Object?> options) =>
      (options.containsKey('allow')
          ? OptionChecks.stringMap('allow', options['allow'])
          : null) ??
      (options.containsKey('extra_evidence')
          ? OptionChecks.stringListMap(
              'extra_evidence',
              options['extra_evidence'],
            )
          : null);

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final project = context.project;
    final plist = project.infoPlist;
    if (plist == null) return;
    final root = plist.root;
    if (!root.has('UIBackgroundModes')) return;
    final modes = root.array('UIBackgroundModes');
    if (modes == null) {
      yield finding(
        '`UIBackgroundModes` must be an array of strings.',
        path: plist.path,
        line: root.lineOf('UIBackgroundModes'),
      );
      return;
    }
    final allow = (context.options['allow'] as Map? ?? const {})
        .cast<String, String>();
    final evidence = <String, List<String>>{
      for (final e in backgroundModeEvidence.entries) e.key: [...e.value],
    };
    for (final MapEntry(:key, :value)
        in (context.options['extra_evidence'] as Map? ?? const {}).entries) {
      evidence
          .putIfAbsent(key as String, () => [])
          .addAll((value as List).cast<String>());
    }

    for (final entry in modes.strings) {
      final mode = entry.value.trim();
      if (!backgroundModes.contains(mode)) {
        yield finding(
          '`$mode` is not a background mode Apple defines.',
          path: plist.path,
          line: entry.line,
        );
        continue;
      }
      if (mode == 'processing' &&
          !root.has('BGTaskSchedulerPermittedIdentifiers')) {
        yield finding(
          '`processing` is declared without '
          '`BGTaskSchedulerPermittedIdentifiers`; BGTaskScheduler refuses to '
          'register tasks that are not listed there.',
          path: plist.path,
          line: entry.line,
        );
      }
      if (allow.containsKey(mode)) continue;
      final plugins = [
        for (final plugin in evidence[mode] ?? const <String>[])
          if (project.links(plugin)) plugin,
      ];
      if (plugins.isEmpty) {
        yield finding(
          '`$mode` is declared but nothing linked in pubspec.lock is known to '
          'need it, and it has no justification under `allow`.',
          path: plist.path,
          line: entry.line,
        );
      } else {
        yield finding(
          '`$mode` is plausibly used by ${plugins.join(', ')}, but has no '
          'recorded justification. Write down how a reviewer reaches the '
          'feature under `allow.$mode`.',
          path: plist.path,
          line: entry.line,
          severity: Severity.warning,
        );
      }
    }
  }
}

/// `ExportOptions.plist` does not let Xcode rewrite the build number.
class ExportOptionsBuildNumberRule extends Rule {
  /// Creates the rule.
  const ExportOptionsBuildNumberRule();

  @override
  String get id => 'export-options-build-number';

  @override
  String get title =>
      'ExportOptions.plist sets manageAppVersionAndBuildNumber to false';

  @override
  RulePlatform get platform => RulePlatform.ios;

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  String get why =>
      'For App Store Connect exports, `manageAppVersionAndBuildNumber` '
      'defaults to YES (see `xcodebuild -help`): Xcode asks App Store Connect at export time and, if '
      'the build number is already taken, silently bumps `CFBundleVersion` in '
      'the exported IPA. The archive, the git tag and the Android build then '
      'disagree about which build this is, with nothing in the log saying '
      'so. With NO, a spent build number fails the upload loudly instead.';

  @override
  String get fix =>
      'Add `<key>manageAppVersionAndBuildNumber</key><false/>` to every '
      'ExportOptions plist used for App Store Connect, and bump the build '
      'number deliberately (e.g. `flutter build ipa --build-number`).';

  @override
  List<String> get docs => const [
    'https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases',
    'https://docs.flutter.dev/deployment/ios#create-a-build-archive-with-xcode',
  ];

  static const _appStoreMethods = {'app-store', 'app-store-connect'};

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final file in context.project.exportOptions) {
      final root = file.root;
      final method = root.string('method')?.trim();
      if (method == null || !_appStoreMethods.contains(method)) continue;
      const key = 'manageAppVersionAndBuildNumber';
      final value = root.boolean(key);
      if (value == false) continue;
      yield finding(
        value == true
            ? '`$key` is true, so Xcode may renumber the build at export.'
            : '`$key` is not set, and it defaults to true for method '
                  '`$method`.',
        path: file.path,
        line: root.has(key) ? root.lineOf(key) : root.lineOf('method'),
      );
    }
  }
}

/// `CFBundleLocalizations` matches the locales the ARB files ship.
class BundleLocalizationsRule extends Rule {
  /// Creates the rule.
  const BundleLocalizationsRule();

  @override
  String get id => 'bundle-localizations';

  @override
  String get title => 'CFBundleLocalizations matches the ARB locales';

  @override
  RulePlatform get platform => RulePlatform.ios;

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  String get why =>
      'A Flutter app localizes in Dart, so its bundle has no `.lproj` '
      'directories — and `.lproj` is what the App Store and iOS infer '
      'languages from. Without `CFBundleLocalizations` the store lists the '
      'app as speaking only its development language, system UI (permission '
      'prompts, share sheets) stays in that language, and nothing fails. A '
      'listed language the app cannot speak is the opposite problem: a '
      'listing that misleads.';

  @override
  String get fix =>
      'List every ARB locale under `CFBundleLocalizations` in Info.plist '
      '(e.g. `<string>en</string><string>pt-BR</string>`), and remove '
      'languages the app has no ARB file for. Set `paths.arb_dir` if your ARB '
      'files are not where `l10n.yaml` says.';

  @override
  List<String> get docs => const [
    'https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundlelocalizations',
    'https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization#localizing-for-ios-updating-the-ios-app-bundle',
  ];

  static String _norm(String locale) =>
      locale.trim().replaceAll('_', '-').toLowerCase();
  static String _lang(String locale) => _norm(locale).split('-').first;

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final project = context.project;
    final plist = project.infoPlist;
    if (plist == null || project.arbLocales.isEmpty) return;
    final root = plist.root;
    const key = 'CFBundleLocalizations';
    final lproj = project.lprojLocales.map(_lang).toSet();
    final arbLangs = project.arbLocales.values.map(_lang).toSet();
    if (!root.has(key)) {
      final uncovered = arbLangs.difference(lproj);
      if (arbLangs.length > 1 && uncovered.isNotEmpty) {
        yield finding(
          'Info.plist has no `$key`, but the ARB files ship '
          '${(arbLangs.toList()..sort()).join(', ')}; the store will list '
          'only the development language.',
          path: plist.path,
        );
      }
      return;
    }
    final declaredEntries = root.array(key)?.strings.toList() ?? const [];
    final declared = declaredEntries.map((e) => _norm(e.value)).toSet();
    final declaredLangs = declared.map(_lang).toSet();
    for (final MapEntry(key: path, value: locale)
        in project.arbLocales.entries) {
      if (declared.contains(_norm(locale)) ||
          declaredLangs.contains(_lang(locale))) {
        continue;
      }
      yield finding(
        '$path ships locale `$locale`, which `$key` does not list.',
        path: plist.path,
        line: root.lineOf(key),
      );
    }
    for (final entry in declaredEntries) {
      final lang = _lang(entry.value);
      if (arbLangs.contains(lang) || lproj.contains(lang)) continue;
      yield finding(
        '`$key` lists `${entry.value.trim()}`, but no ARB file or .lproj '
        'directory provides it.',
        path: plist.path,
        line: entry.line,
      );
    }
  }
}

/// Push-capable apps carry the `aps-environment` entitlement.
class PushEntitlementRule extends Rule {
  /// Creates the rule.
  const PushEntitlementRule();

  @override
  String get id => 'push-entitlement';

  @override
  String get title => 'Apps that receive pushes carry aps-environment';

  @override
  RulePlatform get platform => RulePlatform.ios;

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  String get why =>
      'Without the `aps-environment` entitlement iOS never issues an APNs '
      'token: the push SDK initialises, the permission prompt appears, and '
      'no notification ever arrives. Nothing fails at build time, and a '
      'reviewer testing a notification feature sees it simply not work.';

  @override
  String get fix =>
      'In Xcode, Runner > Signing & Capabilities > + Capability > Push '
      'Notifications. That writes `aps-environment` into the entitlements '
      'file; the value is rewritten to `production` at App Store export.';

  @override
  List<String> get docs => const [
    'https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment',
    'https://firebase.google.com/docs/cloud-messaging/flutter/client#ios',
  ];

  static const _pushSdks = [
    'firebase_messaging',
    'onesignal_flutter',
    'airship_flutter',
  ];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final project = context.project;
    final plist = project.infoPlist;
    if (plist == null) return;
    final reasons = [
      for (final sdk in _pushSdks)
        if (project.links(sdk)) sdk,
      if (plist.root
              .array('UIBackgroundModes')
              ?.strings
              .any((s) => s.value.trim() == 'remote-notification') ??
          false)
        'UIBackgroundModes remote-notification',
    ];
    const key = 'aps-environment';
    for (final file in project.entitlements) {
      final value = file.root[key];
      if (value == null) continue;
      final string = file.root.string(key);
      if (string != 'development' && string != 'production') {
        yield finding(
          '`$key` must be "development" or "production".',
          path: file.path,
          line: file.root.lineOf(key),
          severity: Severity.error,
        );
      }
    }
    if (reasons.isEmpty) return;
    if (project.entitlements.any((f) => f.root.has(key))) return;
    yield finding(
      'No entitlements file declares `$key`, but ${reasons.join(', ')} '
      'expect${reasons.length == 1 ? 's' : ''} push notifications.',
      path: project.entitlements.isEmpty
          ? plist.path
          : project.entitlements.first.path,
    );
  }
}
