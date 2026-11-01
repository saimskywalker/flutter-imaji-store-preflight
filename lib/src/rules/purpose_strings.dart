import '../data/linked_api_references.dart';
import '../data/plugin_requirements.dart';
import '../finding.dart';
import '../plist.dart';
import '../rule.dart';

const _purposeDocs = [
  'https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources',
  'https://developer.apple.com/design/human-interface-guidelines/privacy#Requesting-permission',
  'https://developer.apple.com/app-store/review/guidelines/#5.1.1',
];

const _whenInUse = 'NSLocationWhenInUseUsageDescription';
const _always = 'NSLocationAlwaysAndWhenInUseUsageDescription';

/// Plugins that need a protected resource have its purpose string.
class PurposeStringMissingRule extends Rule {
  /// Creates the rule. [linkedReferences] replaces the built-in
  /// `linkedApiReferences` table (for tests).
  const PurposeStringMissingRule({this.linkedReferences = linkedApiReferences});

  /// Protected-API references plugins bring in without requesting the
  /// permission, by package name.
  final Map<String, LinkedApiReference> linkedReferences;

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
      'simulator run that never reaches the permission prompt. The upload '
      'check is static: a protected API that a bundled native SDK only '
      'references (linked, never requested) needs its key too, and a '
      'CoreLocation reference usually includes the Always authorization API, '
      'so both location keys are asked for.';

  @override
  String get fix =>
      'Add the key to ios/Runner/Info.plist with a sentence that names the '
      'feature and gives an example (see `purpose-string-quality`). When a '
      'dependency only references the API, add the key anyway with a '
      'sentence saying the app does not use the resource and why the key is '
      'present (see `purpose-string-quality` -> `linked_only`); deleting it '
      'only fails the next upload. Extend the plugin table with the '
      '`required_by_plugin` option, and record SDKs that only reference an '
      'API with `linked_by_plugin`.';

  @override
  List<String> get docs => [
    ..._purposeDocs,
    'https://developer.apple.com/documentation/bundleresources/information-property-list/nslocationwheninuseusagedescription',
    'https://developer.apple.com/documentation/bundleresources/information-property-list/nslocationalwaysandwheninuseusagedescription',
  ];

  @override
  Set<String> get optionKeys => const {
    'required_by_plugin',
    'linked_by_plugin',
  };

  @override
  String? validateOptions(Map<String, Object?> options) {
    for (final key in const ['required_by_plugin', 'linked_by_plugin']) {
      if (options.containsKey(key)) {
        final error = OptionChecks.stringListMap(key, options[key]);
        if (error != null) return error;
      }
    }
    return null;
  }

  static Map<String, List<String>> _option(
    RuleContext context,
    String option,
  ) => {
    for (final MapEntry(:key, :value)
        in (context.options[option] as Map? ?? const {}).entries)
      key as String: (value as List).cast<String>(),
  };

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final project = context.project;
    final plist = project.infoPlist;
    if (plist == null) return;
    final table = <String, List<String>>{
      ...purposeStringsByPlugin,
      ..._option(context, 'required_by_plugin'),
    };
    final needs = <String, List<String>>{};
    for (final MapEntry(key: plugin, value: keys) in table.entries) {
      if (!project.links(plugin)) continue;
      for (final key in keys) {
        needs.putIfAbsent(key, () => []).add(plugin);
      }
    }

    // Linked-only references: package to (keys, label for messages).
    final linked = <String, (List<String>, String)>{
      for (final MapEntry(key: plugin, value: row) in linkedReferences.entries)
        plugin: (row.keys, '$plugin ${row.versions}'),
      for (final MapEntry(key: plugin, value: keys) in _option(
        context,
        'linked_by_plugin',
      ).entries)
        plugin: (keys, plugin),
    };
    final references = <String, List<String>>{};
    for (final MapEntry(key: plugin, value: (keys, label)) in linked.entries) {
      if (!project.links(plugin)) continue;
      final expanded = {
        ...keys,
        if (keys.contains(_whenInUse) || keys.contains(_always)) ...[
          _whenInUse,
          _always,
        ],
      };
      for (final key in expanded) {
        references.putIfAbsent(key, () => []).add(label);
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
    for (final MapEntry(key: key, value: plugins) in references.entries) {
      if (needs.containsKey(key) || plist.root.has(key)) continue;
      final location = key == _whenInUse || key == _always
          ? ' A CoreLocation reference usually includes the Always '
                'authorization API, so both `$_whenInUse` and `$_always` '
                'are needed.'
          : '';
      yield finding(
        '`$key` is missing: ${plugins.join(', ')} '
        '${plugins.length == 1 ? 'references' : 'reference'} the protected '
        'API behind it (referenced, not requested). App Store Connect '
        'refuses the upload (ITMS-90683) without the key even if the app '
        'never asks for the permission.$location Add it with a sentence '
        'saying the app does not use the resource and why the key is '
        'present.',
        path: plist.path,
      );
    }
    if (plist.root.has(_always) &&
        !plist.root.has(_whenInUse) &&
        !needs.containsKey(_whenInUse) &&
        !references.containsKey(_whenInUse)) {
      yield finding(
        '`$_always` is present without `$_whenInUse`; iOS requires both '
        'before it will ask for Always access.',
        path: plist.path,
        line: plist.root.lineOf(_always),
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
      'cleared processing, costing a full review cycle. A key that is only '
      'there because a bundled SDK references the API (ITMS-90683 is a '
      'static check) cannot give an example of a use that does not exist; '
      'the honest string says the app does not use the resource and why the '
      'key is present, and inventing a feature would break guidelines '
      '5.1.1(ii) and 2.3. Such a string is false, and shows in the system '
      'prompt, once a plugin that requests the permission is linked.';

  @override
  String get fix =>
      'Write one or two sentences: which feature uses the resource and a '
      'concrete example. "Your microphone records the voice notes you send '
      'in chat — for example, a reply to a friend\'s photo." For a key a '
      'dependency only references, say that the app does not use the '
      'resource and why the key is present: "This app does not use your '
      'location. A third-party SDK included in the app references location '
      'APIs, so iOS requires this text; the app never requests location '
      'access." Such strings are recognised by their English wording; list '
      'a key you have checked by hand (another language, other phrasing) '
      'under `linked_only` (key -> why it is there). Never delete the key to '
      'silence a finding; the next upload fails without it. Tune the '
      'heuristics with `min_words`, `require_example`, `app_names`, '
      '`extra_example_markers` and `extra_unused_markers`.';

  @override
  List<String> get docs => [
    ..._purposeDocs,
    'https://developer.apple.com/app-store/review/guidelines/#2.3',
  ];

  @override
  Set<String> get optionKeys => const {
    'min_words',
    'require_example',
    'app_names',
    'extra_example_markers',
    'extra_unused_markers',
    'linked_only',
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
    for (final key in const [
      'app_names',
      'extra_example_markers',
      'extra_unused_markers',
    ]) {
      if (options.containsKey(key)) {
        final error = OptionChecks.stringList(key, options[key]);
        if (error != null) return error;
      }
    }
    if (options.containsKey('linked_only')) {
      return OptionChecks.stringMap('linked_only', options['linked_only']);
    }
    return null;
  }

  /// Wording that says the app does not use, request or access a resource.
  /// "Not used for advertising" describes a limit on a real use, so `used`
  /// followed by `for` or `to` does not count.
  static final _unused = RegExp(
    r"\b(?:(?:does|do|will|would|did)\s+not|doesn't|don't|won't|never)\s+"
    r'(?:use|uses|request|requests|access|accesses|ask|asks)\b'
    r"|\b(?:not|never|isn't|aren't)\s+used\b(?!\s+(?:for|to)\b)"
    r'|\bunused\b',
  );

  /// Wording that says why a key for an unused resource is present: names a
  /// component or says the key is required.
  static final _keyReason = RegExp(
    r'\b(?:sdks?|librar(?:y|ies)|frameworks?|dependenc(?:y|ies)|'
    r'third[- ]party|plugins?|packages?|components?|modules?|'
    r'references?|referenced|linked|links|includes?|included|'
    r'bundles?|bundled|requires?|required|because)\b',
  );

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
    final unusedMarkers =
        (context.options['extra_unused_markers'] as List? ?? const [])
            .cast<String>()
            .map((m) => m.toLowerCase())
            .toList();
    final linkedOnly = (context.options['linked_only'] as Map? ?? const {})
        .cast<String, String>();

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
      final lower = text.toLowerCase().replaceAll('’', "'");
      final declared = linkedOnly.containsKey(key);
      final saysUnused =
          _unused.hasMatch(lower) || unusedMarkers.any(lower.contains);
      final givesReason = _keyReason.hasMatch(lower);
      final givesExample = markers.any(lower.contains);
      final content = contentWords(text, key, appNameWords);
      if (content.length < 2) {
        yield finding(
          declared || saysUnused
              ? '`$key` is too short for a key the app does not use; say '
                    'that the app does not use the resource and why the key '
                    'is present (the dependency that references the API, or '
                    'that iOS requires the key). Current text: "$text"'
              : '`$key` only restates the permission; name the feature that '
                    'uses it and give an example. Current text: "$text"',
          path: plist.path,
          line: line,
        );
        continue;
      }
      // A "declared, not used" string: listed under `linked_only` (checked
      // by hand, so the English wording heuristics are skipped), or worded
      // as one: says the app does not use the resource, says why the key
      // exists, and gives no example of a use.
      if (declared || (saysUnused && givesReason && !givesExample)) {
        final requesting = [
          for (final MapEntry(key: plugin, value: keys)
              in purposeStringsByPlugin.entries)
            if (keys.contains(key) && context.project.links(plugin)) plugin,
        ];
        if (requesting.isNotEmpty) {
          final direct = requesting.any(context.project.linksDirectly);
          yield finding(
            '`$key` says the app does not use the resource, but '
            '${requesting.join(', ')} '
            '${requesting.length == 1 ? 'is' : 'are'} linked'
            '${direct ? '' : ' (pulled in by another package)'} and '
            '${requesting.length == 1 ? 'requests' : 'request'} that '
            'permission; users see this text in the permission prompt. '
            'Describe the feature that uses it instead.',
            path: plist.path,
            line: line,
            severity: direct ? null : Severity.warning,
          );
        }
        continue;
      }
      if (saysUnused && !givesReason && !givesExample) {
        yield finding(
          '`$key` says the app does not use the resource but not why the key '
          'is present; name the dependency that references the API or say '
          'iOS requires the key: "$text".',
          path: plist.path,
          line: line,
          severity: Severity.warning,
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
      if (requireExample && !givesExample) {
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
