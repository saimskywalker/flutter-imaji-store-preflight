import '../data/plugin_requirements.dart';
import '../finding.dart';
import '../plist.dart';
import '../rule.dart';

const _purposeDocs = [
  'https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources',
  'https://developer.apple.com/design/human-interface-guidelines/privacy#Requesting-permission',
  'https://developer.apple.com/app-store/review/guidelines/#5.1.1',
];

/// Plugins that need a protected resource have its purpose string.
class PurposeStringMissingRule extends Rule {
  /// Creates the rule.
  const PurposeStringMissingRule();

  @override
  String get id => 'purpose-string-missing';

  @override
  String get title => 'Linked plugins have the purpose strings they need';

  @override
  RulePlatform get platform => RulePlatform.ios;

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  String get why =>
      'App Store Connect rejects an upload whose code references a protected '
      'resource without its Info.plist purpose string (ITMS-90683, "Missing '
      'purpose string"), and iOS terminates the app the first time it asks '
      'for a permission whose string is missing. Neither shows up in a '
      'simulator run that never reaches the permission prompt.';

  @override
  String get fix =>
      'Add the key to ios/Runner/Info.plist with a sentence that names the '
      'feature and gives an example (see `purpose-string-quality`). Extend '
      'the plugin table with the `required_by_plugin` option.';

  @override
  List<String> get docs => [
    ..._purposeDocs,
    'https://developer.apple.com/documentation/bundleresources/information-property-list/nslocationwheninuseusagedescription',
  ];

  @override
  Set<String> get optionKeys => const {'required_by_plugin'};

  @override
  String? validateOptions(Map<String, Object?> options) =>
      OptionChecks.stringListMap(
        'required_by_plugin',
        options['required_by_plugin'],
      );

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final project = context.project;
    final plist = project.infoPlist;
    if (plist == null) return;
    final table = <String, List<String>>{
      ...purposeStringsByPlugin,
      for (final MapEntry(:key, :value)
          in (context.options['required_by_plugin'] as Map? ?? const {})
              .entries)
        key as String: (value as List).cast<String>(),
    };
    final needs = <String, List<String>>{};
    for (final MapEntry(key: plugin, value: keys) in table.entries) {
      if (!project.links(plugin)) continue;
      for (final key in keys) {
        needs.putIfAbsent(key, () => []).add(plugin);
      }
    }
    for (final MapEntry(key: key, value: plugins) in needs.entries) {
      if (!plist.root.has(key)) {
        yield finding(
          '`$key` is missing, but ${plugins.join(', ')} '
          '${plugins.length == 1 ? 'needs' : 'need'} it.',
          path: plist.path,
        );
      }
    }
    const always = 'NSLocationAlwaysAndWhenInUseUsageDescription';
    const whenInUse = 'NSLocationWhenInUseUsageDescription';
    if (plist.root.has(always) &&
        !plist.root.has(whenInUse) &&
        !needs.containsKey(whenInUse)) {
      yield finding(
        '`$always` is present without `$whenInUse`; iOS requires both '
        'before it will ask for Always access.',
        path: plist.path,
        line: plist.root.lineOf(always),
      );
    }
  }
}

/// Purpose strings describe a use, not the permission.
class PurposeStringQualityRule extends Rule {
  /// Creates the rule.
  const PurposeStringQualityRule();

  @override
  String get id => 'purpose-string-quality';

  @override
  String get title =>
      'Purpose strings name a feature and give an example, not restate the '
      'permission';

  @override
  RulePlatform get platform => RulePlatform.ios;

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  String get why =>
      'Guideline 5.1.1(ii) requires a purpose string to clearly and completely '
      'describe how the app uses the data. "MyApp needs microphone access to '
      'record video" is a restatement of the permission, not a description '
      'of a use, and reviewers reject it — after the build has already '
      'cleared processing, costing a full review cycle.';

  @override
  String get fix =>
      'Write one or two sentences: which feature uses the resource and a '
      'concrete example. "Your microphone records the voice notes you send '
      'in chat — for example, a reply to a friend\'s photo." Tune the '
      'heuristics with `min_words`, `require_example`, `app_names` and '
      '`extra_example_markers`.';

  @override
  List<String> get docs => _purposeDocs;

  @override
  Set<String> get optionKeys => const {
    'min_words',
    'require_example',
    'app_names',
    'extra_example_markers',
  };

  @override
  String? validateOptions(Map<String, Object?> options) {
    final minWords = options['min_words'];
    if (options.containsKey('min_words') &&
        (minWords is! int || minWords < 0)) {
      return '`min_words` must be a non-negative integer';
    }
    if (options.containsKey('require_example') &&
        options['require_example'] is! bool) {
      return '`require_example` must be true or false';
    }
    for (final key in const ['app_names', 'extra_example_markers']) {
      if (options.containsKey(key)) {
        final error = OptionChecks.stringList(key, options[key]);
        if (error != null) return error;
      }
    }
    return null;
  }

  static final _word = RegExp(r"[a-z][a-z'’]*");
  static final _variable = RegExp(r'\$\([^)]*\)|\$\{[^}]*\}');
  static final _placeholder = RegExp(
    r'\b(todo|fixme|tbd|lorem|placeholder|usage description)\b',
    caseSensitive: false,
  );
  static final _camel = RegExp('[A-Z][a-z]+');

  /// Words that describe [key]'s permission itself.
  static Set<String> vocabularyFor(String key) {
    final derived = _camel
        .allMatches(
          key
              .replaceFirst(RegExp('^NS'), '')
              .replaceFirst('UsageDescription', ''),
        )
        .map((m) => m.group(0)!.toLowerCase());
    return {...?permissionVocabulary[key], ...derived};
  }

  /// The words of [text] that say something beyond the permission itself.
  static Set<String> contentWords(
    String text,
    String key,
    Set<String> appNameWords,
  ) {
    final vocab = vocabularyFor(key);
    return {
          for (final m in _word.allMatches(
            text.replaceAll(_variable, ' ').toLowerCase(),
          ))
            m.group(0)!.replaceAll('’', "'"),
        }
        .where(
          (w) =>
              !purposeFiller.contains(w) &&
              !vocab.contains(w) &&
              !appNameWords.contains(w) &&
              !(w.endsWith("'s") &&
                  (appNameWords.contains(w.substring(0, w.length - 2)) ||
                      purposeFiller.contains(w.substring(0, w.length - 2)))),
        )
        .toSet();
  }

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final plist = context.project.infoPlist;
    if (plist == null) return;
    final root = plist.root;
    final minWords = context.options['min_words'] as int? ?? 8;
    final requireExample = context.options['require_example'] as bool? ?? true;
    final markers = [
      ...exampleMarkers,
      ...(context.options['extra_example_markers'] as List? ?? const [])
          .cast<String>()
          .map((m) => m.toLowerCase()),
    ];
    final appNameWords = <String>{
      for (final name in [
        root.string('CFBundleDisplayName'),
        root.string('CFBundleName'),
        ...(context.options['app_names'] as List? ?? const []).cast<String>(),
      ])
        if (name != null && !_variable.hasMatch(name))
          ..._word.allMatches(name.toLowerCase()).map((m) => m.group(0)!),
    };

    for (final MapEntry(:key, :value) in root.entries.entries) {
      if (!key.endsWith('UsageDescription')) continue;
      final line = root.lineOf(key);
      if (value is! PlistString) {
        yield finding('`$key` must be a string.', path: plist.path, line: line);
        continue;
      }
      final text = value.value.trim();
      if (text.replaceAll(_variable, '').trim().isEmpty) {
        yield finding('`$key` is empty.', path: plist.path, line: line);
        continue;
      }
      if (_placeholder.hasMatch(text)) {
        yield finding(
          '`$key` is a placeholder: "$text".',
          path: plist.path,
          line: line,
        );
        continue;
      }
      final content = contentWords(text, key, appNameWords);
      if (content.length < 2) {
        yield finding(
          '`$key` only restates the permission; name the feature that uses '
          'it and give an example. Current text: "$text"',
          path: plist.path,
          line: line,
        );
        continue;
      }
      final problems = <String>[];
      final wordCount = _word.allMatches(text.toLowerCase()).length;
      if (wordCount < minWords) {
        problems.add(
          'is $wordCount words, too short to name a feature and '
          'give an example (minimum $minWords)',
        );
      }
      final lower = text.toLowerCase();
      if (requireExample && !markers.any(lower.contains)) {
        problems.add('gives no example ("for example", "such as", …)');
      }
      if (problems.isNotEmpty) {
        yield finding(
          '`$key` ${problems.join(' and ')}: "$text".',
          path: plist.path,
          line: line,
          severity: Severity.warning,
        );
      }
    }
  }
}
