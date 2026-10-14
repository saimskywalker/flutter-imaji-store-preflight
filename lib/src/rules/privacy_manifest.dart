import 'package:path/path.dart' as p;

import '../data/apple_privacy.dart';
import '../data/sdk_data_types.dart';
import '../finding.dart';
import '../plist.dart';
import '../rule.dart';

/// One entry of `NSPrivacyCollectedDataTypes`.
class CollectedDataEntry {
  /// Creates an entry.
  const CollectedDataEntry({
    required this.dict,
    required this.type,
    required this.linked,
    required this.tracking,
    required this.purposes,
  });

  /// The entry's dictionary.
  final PlistDict dict;

  /// `NSPrivacyCollectedDataType`, as written (with prefix), if a string.
  final String? type;

  /// `NSPrivacyCollectedDataTypeLinked`, if a boolean.
  final bool? linked;

  /// `NSPrivacyCollectedDataTypeTracking`, if a boolean.
  final bool? tracking;

  /// `NSPrivacyCollectedDataTypePurposes` string items.
  final List<PlistString> purposes;

  /// The type without Apple's prefix.
  String? get shortType => type?.replaceFirst(collectedDataTypePrefix, '');
}

/// Reads the collected data entries of a manifest. Non-dict items are skipped
/// (the values rule reports them).
List<CollectedDataEntry> collectedDataEntries(PlistDict manifest) => [
  for (final item
      in manifest.array('NSPrivacyCollectedDataTypes')?.items ??
          const <PlistValue>[])
    if (item is PlistDict)
      CollectedDataEntry(
        dict: item,
        type: item.string('NSPrivacyCollectedDataType')?.trim(),
        linked: item.boolean('NSPrivacyCollectedDataTypeLinked'),
        tracking: item.boolean('NSPrivacyCollectedDataTypeTracking'),
        purposes:
            item
                .array('NSPrivacyCollectedDataTypePurposes')
                ?.strings
                .toList() ??
            const [],
      ),
];

/// The app has a privacy manifest, and Xcode actually ships it.
class PrivacyManifestPresentRule extends Rule {
  /// Creates the rule.
  const PrivacyManifestPresentRule();

  @override
  String get id => 'privacy-manifest-present';

  @override
  String get title => 'The app target ships a PrivacyInfo.xcprivacy';

  @override
  RulePlatform get platform => RulePlatform.ios;

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  String get why =>
      'Since 1 May 2024 App Store Connect refuses uploads whose code uses a '
      'required-reason API without a declared reason (ITMS-91053), and the '
      "app's own manifest is where the data it collects is declared. A "
      'manifest that exists on disk but is not a member of the Runner target '
      'is never copied into the bundle, so the build ships with none — '
      'silently, because nothing fails at build time.';

  @override
  String get fix =>
      'In Xcode, File > New > File > App Privacy, add it to the Runner target. '
      'If the file already exists, select it and tick Runner under Target '
      'Membership so it appears in Build Phases > Copy Bundle Resources.';

  @override
  List<String> get docs => privacyManifestDocs;

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final project = context.project;
    if (project.infoPlist == null) return;
    final manifest = project.privacyManifest;
    if (manifest == null) {
      if (project.problems.any((pr) => pr.path.endsWith('.xcprivacy'))) return;
      yield finding(
        'No privacy manifest at ios/Runner/PrivacyInfo.xcprivacy (or the '
        'path configured under `paths.privacy_manifest`).',
        path: project.infoPlist!.path,
      );
      return;
    }
    final pbx = project.xcodeProject;
    final name = p.basename(manifest.path);
    if (pbx != null && !pbx.text.contains('$name in Resources')) {
      yield finding(
        '$name exists but is not in any target\'s Copy Bundle Resources '
        'phase, so it never reaches the built app.',
        path: pbx.path,
        severity: Severity.error,
      );
    }
  }
}

/// Every key and value in the manifest is one Apple defines.
class PrivacyManifestValuesRule extends Rule {
  /// Creates the rule.
  const PrivacyManifestValuesRule();

  @override
  String get id => 'privacy-manifest-values';

  @override
  String get title =>
      'Privacy manifest data types, purposes and API reasons are Apple values';

  @override
  RulePlatform get platform => RulePlatform.ios;

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  String get why =>
      'Xcode does not validate the manifest. A misspelt data type or purpose '
      'declares nothing at all, so the privacy report Apple generates from it '
      'disagrees with the App Store privacy label; a required-reason API with '
      'an unknown reason code is treated as undeclared and the upload is '
      'refused with ITMS-91053.';

  @override
  String get fix =>
      'Use the exact constants from Apple\'s documentation (they are '
      'case-sensitive: `NSPrivacyCollectedDataTypePhotosorVideos` has a '
      'lowercase "or"). Give every collected type its Linked and Tracking '
      'booleans and at least one purpose. If Apple has added a value this '
      'tool does not know yet, list it under `extra_data_types`, '
      '`extra_purposes` or `extra_api_reasons` for this rule.';

  @override
  List<String> get docs => privacyManifestDocs;

  @override
  Set<String> get optionKeys => const {
    'extra_data_types',
    'extra_purposes',
    'extra_api_reasons',
  };

  @override
  String? validateOptions(Map<String, Object?> options) =>
      (options.containsKey('extra_data_types')
          ? OptionChecks.stringList(
              'extra_data_types',
              options['extra_data_types'],
            )
          : null) ??
      (options.containsKey('extra_purposes')
          ? OptionChecks.stringList('extra_purposes', options['extra_purposes'])
          : null) ??
      (options.containsKey('extra_api_reasons')
          ? OptionChecks.stringListMap(
              'extra_api_reasons',
              options['extra_api_reasons'],
            )
          : null);

  static const _topLevel = {
    'NSPrivacyTracking',
    'NSPrivacyTrackingDomains',
    'NSPrivacyCollectedDataTypes',
    'NSPrivacyAccessedAPITypes',
  };

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final file = context.project.privacyManifest;
    if (file == null) return;
    final path = file.path;
    final root = file.root;

    String strip(String value, String prefix) =>
        value.startsWith(prefix) ? value.substring(prefix.length) : value;
    final types = {
      ...collectedDataTypes,
      ...(context.options['extra_data_types'] as List? ?? const [])
          .cast<String>()
          .map((t) => strip(t, collectedDataTypePrefix)),
    };
    final purposes = {
      ...collectionPurposes,
      ...(context.options['extra_purposes'] as List? ?? const [])
          .cast<String>()
          .map((t) => strip(t, purposePrefix)),
    };
    final apis = <String, Set<String>>{
      for (final e in requiredReasonApis.entries) e.key: {...e.value},
    };
    final extraReasons = context.options['extra_api_reasons'] as Map? ?? {};
    for (final MapEntry(:key, :value) in extraReasons.entries) {
      apis
          .putIfAbsent(strip(key as String, apiCategoryPrefix), () => {})
          .addAll((value as List).cast<String>());
    }

    for (final key in root.entries.keys) {
      if (!_topLevel.contains(key)) {
        yield finding(
          'Unknown top-level key `$key`; Apple reads only '
          '${_topLevel.map((k) => '`$k`').join(', ')}.',
          path: path,
          line: root.lineOf(key),
          severity: Severity.warning,
        );
      }
    }

    if (root.has('NSPrivacyTracking') &&
        root.boolean('NSPrivacyTracking') == null) {
      yield finding(
        '`NSPrivacyTracking` must be <true/> or <false/>.',
        path: path,
        line: root.lineOf('NSPrivacyTracking'),
      );
    }
    if (root.has('NSPrivacyTrackingDomains')) {
      final domains = root.array('NSPrivacyTrackingDomains');
      if (domains == null ||
          domains.items.any(
            (d) => d is! PlistString || d.value.trim().isEmpty,
          )) {
        yield finding(
          '`NSPrivacyTrackingDomains` must be an array of domain strings.',
          path: path,
          line: root.lineOf('NSPrivacyTrackingDomains'),
        );
      }
    }

    // Collected data.
    if (root.has('NSPrivacyCollectedDataTypes')) {
      final array = root.array('NSPrivacyCollectedDataTypes');
      if (array == null) {
        yield finding(
          '`NSPrivacyCollectedDataTypes` must be an array of dictionaries.',
          path: path,
          line: root.lineOf('NSPrivacyCollectedDataTypes'),
        );
      } else {
        for (final item in array.items.where((i) => i is! PlistDict)) {
          yield finding(
            '`NSPrivacyCollectedDataTypes` items must be dictionaries.',
            path: path,
            line: item.line,
          );
        }
      }
      final seen = <String>{};
      for (final entry in collectedDataEntries(root)) {
        final dict = entry.dict;
        final type = entry.type;
        if (type == null) {
          yield finding(
            'A collected data entry has no `NSPrivacyCollectedDataType` '
            'string.',
            path: path,
            line: dict.line,
          );
          continue;
        }
        final short = entry.shortType!;
        if (!type.startsWith(collectedDataTypePrefix) ||
            !types.contains(short)) {
          yield finding(
            '`$type` is not a data type Apple defines${_suggest(short, types, collectedDataTypePrefix)}.',
            path: path,
            line: dict.lineOf('NSPrivacyCollectedDataType'),
          );
        } else if (!seen.add(short)) {
          yield finding(
            '`$type` is declared more than once; merge the entries and their '
            'purposes.',
            path: path,
            line: dict.lineOf('NSPrivacyCollectedDataType'),
          );
        }
        for (final key in const [
          'NSPrivacyCollectedDataTypeLinked',
          'NSPrivacyCollectedDataTypeTracking',
        ]) {
          if (dict.boolean(key) == null) {
            yield finding(
              '`$type` needs `$key` as <true/> or <false/>.',
              path: path,
              line: dict.has(key) ? dict.lineOf(key) : dict.line,
            );
          }
        }
        final purposeArray = dict.array('NSPrivacyCollectedDataTypePurposes');
        if (purposeArray == null || entry.purposes.isEmpty) {
          yield finding(
            '`$type` declares no `NSPrivacyCollectedDataTypePurposes`; every '
            'collected type needs at least one purpose.',
            path: path,
            line: dict.has('NSPrivacyCollectedDataTypePurposes')
                ? dict.lineOf('NSPrivacyCollectedDataTypePurposes')
                : dict.line,
          );
        }
        for (final purpose in entry.purposes) {
          final value = purpose.value.trim();
          if (!value.startsWith(purposePrefix) ||
              !purposes.contains(value.substring(purposePrefix.length))) {
            yield finding(
              '`$type`: `$value` is not a purpose Apple defines'
              '${_suggest(strip(value, purposePrefix), purposes, purposePrefix)}.',
              path: path,
              line: purpose.line,
            );
          }
        }
      }
    }

    // Required-reason APIs.
    if (root.has('NSPrivacyAccessedAPITypes')) {
      final array = root.array('NSPrivacyAccessedAPITypes');
      if (array == null) {
        yield finding(
          '`NSPrivacyAccessedAPITypes` must be an array of dictionaries.',
          path: path,
          line: root.lineOf('NSPrivacyAccessedAPITypes'),
        );
        return;
      }
      for (final item in array.items) {
        if (item is! PlistDict) {
          yield finding(
            '`NSPrivacyAccessedAPITypes` items must be dictionaries.',
            path: path,
            line: item.line,
          );
          continue;
        }
        final category = item.string('NSPrivacyAccessedAPIType')?.trim();
        if (category == null) {
          yield finding(
            'An accessed API entry has no `NSPrivacyAccessedAPIType` string.',
            path: path,
            line: item.line,
          );
          continue;
        }
        final short = strip(category, apiCategoryPrefix);
        final allowed = apis[short];
        if (!category.startsWith(apiCategoryPrefix) || allowed == null) {
          yield finding(
            '`$category` is not a required-reason API category'
            '${_suggest(short, apis.keys.toSet(), apiCategoryPrefix)}.',
            path: path,
            line: item.lineOf('NSPrivacyAccessedAPIType'),
          );
          continue;
        }
        final reasons =
            item.array('NSPrivacyAccessedAPITypeReasons')?.strings.toList() ??
            const <PlistString>[];
        if (reasons.isEmpty) {
          yield finding(
            '`$category` lists no `NSPrivacyAccessedAPITypeReasons`; an API '
            'without an approved reason counts as undeclared.',
            path: path,
            line: item.line,
          );
        }
        for (final reason in reasons) {
          if (!allowed.contains(reason.value.trim())) {
            yield finding(
              '`$category`: `${reason.value}` is not an approved reason; use '
              'one of ${(allowed.toList()..sort()).join(', ')}.',
              path: path,
              line: reason.line,
            );
          }
        }
      }
    }
  }
}

/// Suggests the closest known value, ignoring case, for a typo.
String _suggest(String value, Set<String> known, String prefix) {
  final lower = value.toLowerCase();
  for (final k in known) {
    if (k.toLowerCase() == lower) return ' (did you mean `$prefix$k`?)';
  }
  return '';
}

/// `NSPrivacyTracking` agrees with the entries and domains.
class PrivacyManifestTrackingRule extends Rule {
  /// Creates the rule.
  const PrivacyManifestTrackingRule();

  @override
  String get id => 'privacy-manifest-tracking';

  @override
  String get title => 'NSPrivacyTracking agrees with entries and domains';

  @override
  RulePlatform get platform => RulePlatform.ios;

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  String get why =>
      'The manifest makes one claim about tracking in three places: '
      '`NSPrivacyTracking`, each entry\'s `NSPrivacyCollectedDataTypeTracking`, '
      'and `NSPrivacyTrackingDomains`. A reviewer compares them with each '
      'other and with the App Store privacy label, and a contradiction the '
      'developer wrote down is the easiest thing to find. iOS also only '
      'blocks the listed domains when tracking is declared, so domains under '
      '`NSPrivacyTracking = false` are a claim nothing enforces.';

  @override
  String get fix =>
      'Decide whether the app tracks (in Apple\'s sense: linking its data with '
      'third-party data for advertising, or sharing it with a data broker). '
      'If not, set every entry\'s Tracking to false and empty '
      '`NSPrivacyTrackingDomains`. If it does, set `NSPrivacyTracking` to '
      'true, list the tracking domains, add `NSUserTrackingUsageDescription` '
      'and update the privacy label in the same change.';

  @override
  List<String> get docs => [
    ...privacyManifestDocs,
    'https://developer.apple.com/app-store/user-privacy-and-data-use/',
  ];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final file = context.project.privacyManifest;
    if (file == null) return;
    final root = file.root;
    final tracks = root.boolean('NSPrivacyTracking') ?? false;
    final domains =
        root.array('NSPrivacyTrackingDomains')?.strings.toList() ?? const [];
    if (!tracks) {
      for (final entry in collectedDataEntries(root)) {
        if (entry.tracking ?? false) {
          yield finding(
            '`${entry.type}` is marked as used for tracking while '
            '`NSPrivacyTracking` is ${root.has('NSPrivacyTracking') ? 'false' : 'absent (false)'}.',
            path: file.path,
            line: entry.dict.lineOf('NSPrivacyCollectedDataTypeTracking'),
          );
        }
      }
      if (domains.isNotEmpty) {
        yield finding(
          '`NSPrivacyTrackingDomains` lists ${domains.length} domain(s) while '
          '`NSPrivacyTracking` is false.',
          path: file.path,
          line: root.lineOf('NSPrivacyTrackingDomains'),
        );
      }
    } else if (domains.isEmpty) {
      yield finding(
        '`NSPrivacyTracking` is true but `NSPrivacyTrackingDomains` is empty; '
        'list the domains that receive tracking data so iOS can block them '
        'until the user allows tracking.',
        path: file.path,
        line: root.lineOf('NSPrivacyTracking'),
        severity: Severity.warning,
      );
    }
  }
}

/// SDKs known to collect data have their data types declared.
class PrivacyManifestSdkDataRule extends Rule {
  /// Creates the rule.
  const PrivacyManifestSdkDataRule();

  @override
  String get id => 'privacy-manifest-sdk-data';

  @override
  String get title =>
      'Collected data covers what the linked SDKs are known to collect';

  @override
  RulePlatform get platform => RulePlatform.ios;

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  String get why =>
      'An empty `NSPrivacyCollectedDataTypes` says the app collects nothing. '
      'With an analytics, crash-reporting, messaging or ads SDK linked, that '
      'contradicts the App Store privacy label the reviewer reads next to it. '
      'Not every SDK ships its own manifest, and static linking can drop one '
      'that does, so what it collects is declared in the app or nowhere.';

  @override
  String get fix =>
      'Add an `NSPrivacyCollectedDataTypes` entry for each listed type, with '
      'Linked/Tracking set to match your privacy label. If an SDK is linked '
      'but its collection is disabled, record that with an `ignore` entry and '
      'a reason. Extend or override the SDK table with the `sdk_data_types` '
      'option (package name to list of types).';

  @override
  List<String> get docs => [
    ...privacyManifestDocs,
    'https://developer.apple.com/app-store/app-privacy-details/',
  ];

  @override
  Set<String> get optionKeys => const {'sdk_data_types'};

  @override
  String? validateOptions(Map<String, Object?> options) =>
      OptionChecks.stringListMap('sdk_data_types', options['sdk_data_types']);

  /// The effective package-to-types table for [options].
  static Map<String, List<String>> table(Map<String, Object?> options) {
    final table = <String, List<String>>{
      for (final e in builtInSdkDataTypes.entries) e.key: e.value.types,
    };
    final extra = options['sdk_data_types'] as Map? ?? const {};
    for (final MapEntry(:key, :value) in extra.entries) {
      table[key as String] = [
        for (final t in (value as List).cast<String>())
          t.replaceFirst(collectedDataTypePrefix, ''),
      ];
    }
    return table;
  }

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final project = context.project;
    final file = project.privacyManifest;
    if (file == null) return;
    final linked = {
      for (final MapEntry(:key, :value) in table(context.options).entries)
        if (value.isNotEmpty && project.links(key)) key: value,
    };
    if (linked.isEmpty) return;
    final declared = {
      for (final e in collectedDataEntries(file.root))
        if (e.shortType != null) e.shortType!,
    };
    final line = file.root.lineOf('NSPrivacyCollectedDataTypes');
    if (declared.isEmpty) {
      yield finding(
        'The manifest declares no collected data, but '
        '${linked.entries.map((e) => '${e.key} (${e.value.join(', ')})').join('; ')} '
        '${linked.length == 1 ? 'is' : 'are'} linked.',
        path: file.path,
        line: line,
      );
      return;
    }
    for (final MapEntry(key: sdk, value: types) in linked.entries) {
      final missing = types.where((t) => !declared.contains(t)).toList();
      if (missing.isEmpty) continue;
      yield finding(
        '$sdk is linked, but the manifest does not declare '
        '${missing.map((t) => '`$collectedDataTypePrefix$t`').join(', ')}.',
        path: file.path,
        line: line,
        severity: Severity.warning,
      );
    }
  }
}

/// `NSUserTrackingUsageDescription` agrees with `NSPrivacyTracking`.
class TrackingUsageDescriptionRule extends Rule {
  /// Creates the rule.
  const TrackingUsageDescriptionRule();

  @override
  String get id => 'tracking-usage-description';

  @override
  String get title =>
      'NSUserTrackingUsageDescription is present exactly when tracking is';

  @override
  RulePlatform get platform => RulePlatform.ios;

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  String get why =>
      'App Store Connect refuses "Add for Review" for a build that carries '
      '`NSUserTrackingUsageDescription` while the app declares no tracking — '
      'the purpose string is itself a claim that the app asks to track. The '
      'other direction fails at run time: calling the App Tracking '
      'Transparency request without the purpose string terminates the app, '
      'and tracking without asking breaks Guideline 5.1.2.';

  @override
  String get fix =>
      'Treat the purpose string, `NSPrivacyTracking` and the privacy label as '
      'one decision. Not tracking: delete the key from Info.plist (and stop '
      'calling the ATT request). Tracking: set `NSPrivacyTracking` to true '
      'and keep a purpose string that says what is tracked and why.';

  @override
  List<String> get docs => const [
    'https://developer.apple.com/documentation/bundleresources/information-property-list/nsusertrackingusagedescription',
    'https://developer.apple.com/documentation/apptrackingtransparency',
    'https://developer.apple.com/app-store/review/guidelines/#5.1.2',
  ];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final project = context.project;
    final plist = project.infoPlist;
    if (plist == null) return;
    const key = 'NSUserTrackingUsageDescription';
    final hasKey = plist.root.has(key);
    final manifest = project.privacyManifest;
    final tracks = manifest?.root.boolean('NSPrivacyTracking') ?? false;
    if (hasKey && !tracks) {
      yield finding(
        manifest == null
            ? '`$key` is present but there is no privacy manifest declaring '
                  'tracking.'
            : '`$key` is present while ${manifest.path} declares '
                  '`NSPrivacyTracking` false.',
        path: plist.path,
        line: plist.root.lineOf(key),
      );
    } else if (!hasKey && tracks) {
      yield finding(
        '${manifest!.path} declares tracking but Info.plist has no `$key`, so '
        'the app cannot ask the user for permission.',
        path: manifest.path,
        line: manifest.root.lineOf('NSPrivacyTracking'),
      );
    } else if (!hasKey && project.links('app_tracking_transparency')) {
      yield finding(
        'app_tracking_transparency is linked but Info.plist has no `$key`; '
        'any call to its request method terminates the app.',
        path: plist.path,
        severity: Severity.warning,
      );
    }
  }
}
