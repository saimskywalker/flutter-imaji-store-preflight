import 'package:storehound/storehound.dart';
import 'package:test/test.dart';

/// A configurable stand-in, so these tests do not depend on real rules.
class _FakeRule extends Rule {
  const _FakeRule(this.id);

  @override
  final String id;
  @override
  String get title => 'Fake';
  @override
  RulePlatform get platform => RulePlatform.general;
  @override
  Severity get defaultSeverity => Severity.warning;
  @override
  String get why => 'Testing.';
  @override
  String get fix => 'None.';
  @override
  List<String> get docs => const ['https://example.com'];
  @override
  Set<String> get optionKeys => const {'allow', 'min_words'};

  @override
  String? validateOptions(Map<String, Object?> options) =>
      (options.containsKey('allow')
          ? OptionChecks.stringMap('allow', options['allow'])
          : null) ??
      (options.containsKey('min_words') && options['min_words'] is! int
          ? '`min_words` must be an integer'
          : null);

  @override
  Iterable<Finding> check(RuleContext context) => const [];
}

const _rules = <Rule>[_FakeRule('alpha'), _FakeRule('beta')];

PreflightConfig parse(String yaml) =>
    PreflightConfig.parse(yaml, _rules, source: 'config.yaml');

Matcher throwsConfig(Object message) => throwsA(
  isA<ConfigException>().having((e) => e.message, 'message', message),
);

void main() {
  test('an empty file is the default configuration', () {
    final config = parse('');
    expect(config.failOn, Severity.error);
    expect(config.rules, isEmpty);
    expect(config.ignores, isEmpty);
  });

  test('reads fail_on, paths, rules and ignores', () {
    final config = parse('''
fail_on: warning
paths:
  info_plist: app/ios/Runner/Info.plist
  export_options: ios/ExportOptions.plist
rules:
  alpha:
    enabled: false
    reason: The app ships one language on purpose.
  beta:
    severity: warning
    min_words: 5
ignore:
  - rule: alpha
    path: ios/Runner/Runner.entitlements
    match: aps-environment
    reason: Pushes are delivered by a web view only.
''');
    expect(config.failOn, Severity.warning);
    expect(config.paths.infoPlist, 'app/ios/Runner/Info.plist');
    expect(config.paths.exportOptions, ['ios/ExportOptions.plist']);
    final disabled = config.forRule('alpha');
    expect(disabled.enabled, isFalse);
    expect(disabled.reason, contains('one language'));
    final quality = config.forRule('beta');
    expect(quality.severity, Severity.warning);
    expect(quality.options, {'min_words': 5});
    expect(config.ignores.single.rule, 'alpha');
  });

  test('fail_on: never disables failing', () {
    expect(parse('fail_on: never').failOn, isNull);
  });

  test('disabling a rule requires a reason', () {
    expect(
      () => parse('rules:\n  alpha: false\n'),
      throwsConfig(contains('needs a reason')),
    );
    expect(
      () => parse('rules:\n  alpha:\n    enabled: false\n'),
      throwsConfig(contains('non-empty `reason`')),
    );
    expect(
      () => parse('rules:\n  alpha:\n    enabled: false\n    reason: " "\n'),
      throwsConfig(contains('non-empty string')),
    );
  });

  test('an ignore entry requires a reason', () {
    expect(
      () => parse('ignore:\n  - rule: alpha\n'),
      throwsConfig(contains('non-empty `reason`')),
    );
  });

  test('unknown rules and keys are errors, with line numbers', () {
    expect(
      () => parse('rules:\n  no-such-rule: true\n'),
      throwsA(
        isA<ConfigException>()
            .having((e) => e.message, 'message', contains('no-such-rule'))
            .having((e) => e.line, 'line', 2),
      ),
    );
    expect(() => parse('colour: red'), throwsConfig(contains('`colour`')));
    expect(
      () => parse('rules:\n  alpha:\n    deny: {}\n'),
      throwsConfig(contains('unknown key `deny`')),
    );
    expect(
      () => parse('ignore:\n  - rule: nope\n    reason: x\n'),
      throwsConfig(contains('unknown rule `nope`')),
    );
  });

  test('rule options are validated by the rule', () {
    expect(
      () => parse('rules:\n  alpha:\n    allow:\n      audio: ""\n'),
      throwsConfig(contains('non-empty string')),
    );
    expect(
      () => parse('rules:\n  beta:\n    min_words: many\n'),
      throwsConfig(contains('must be an integer')),
    );
  });

  test('bad severities and fail_on values are errors', () {
    expect(() => parse('fail_on: sometimes'), throwsConfig(contains('never')));
    expect(
      () => parse('rules:\n  alpha:\n    severity: fatal\n'),
      throwsConfig(contains('error, warning or info')),
    );
  });

  test('YAML syntax errors carry a line', () {
    expect(
      () => parse('rules:\n  a: [\n'),
      throwsA(isA<ConfigException>().having((e) => e.line, 'line', isNotNull)),
    );
  });

  group('checks', () {
    Matcher throwsConfigAt(Object message, int line) => throwsA(
      isA<ConfigException>()
          .having((e) => e.message, 'message', message)
          .having((e) => e.line, 'line', line),
    );

    test('reads Info.plist and AndroidManifest checks', () {
      final config = parse('''
checks:
  ats-no-arbitrary-loads:
    file: info_plist
    key: NSAppTransportSecurity.NSAllowsArbitraryLoads
    absent_or_equals: false
    reason: All traffic is HTTPS.
  no-media-permissions:
    file: android_manifest
    element: uses-permission
    attribute: android:name
    none_of: [android.permission.READ_MEDIA_IMAGES]
    severity: warning
    reason: The app uses the system photo picker only.
''');
      final [plist, manifest] = config.checkRules;
      expect(plist.id, 'check:ats-no-arbitrary-loads');
      expect(plist.file, CheckFile.infoPlist);
      expect(plist.keyPath, [
        'NSAppTransportSecurity',
        'NSAllowsArbitraryLoads',
      ]);
      expect(plist.operator, CheckOperator.absentOrEquals);
      expect(plist.expected, false);
      expect(plist.defaultSeverity, Severity.error);
      expect(plist.why, 'All traffic is HTTPS.');
      expect(manifest.file, CheckFile.androidManifest);
      expect(manifest.element, 'uses-permission');
      expect(manifest.attribute, 'android:name');
      expect(manifest.expected, ['android.permission.READ_MEDIA_IMAGES']);
      expect(manifest.defaultSeverity, Severity.warning);
    });

    test('a key can be a list of literal parts', () {
      final check = parse('''
checks:
  subdomains:
    file: info_plist
    key: [NSAppTransportSecurity, NSExceptionDomains, example.com]
    exists: true
    reason: The API host is pinned.
''').checkRules.single;
      expect(check.keyPath, [
        'NSAppTransportSecurity',
        'NSExceptionDomains',
        'example.com',
      ]);
    });

    test('rules and ignore can name a check', () {
      final config = parse('''
checks:
  no-backup:
    file: android_manifest
    element: application
    attribute: android:allowBackup
    equals: "false"
    reason: Tokens live in shared preferences.
rules:
  check:no-backup:
    severity: warning
ignore:
  - rule: check:no-backup
    reason: Being fixed in the next release.
''');
      expect(config.forRule('check:no-backup').severity, Severity.warning);
      expect(config.ignores.single.rule, 'check:no-backup');
      expect(
        () => parse('ignore:\n  - rule: check:nope\n    reason: x\n'),
        throwsConfig(contains('unknown rule `check:nope`')),
      );
    });

    test('every check needs a reason', () {
      expect(
        () => parse('''
checks:
  pin:
    file: info_plist
    key: ITSAppUsesNonExemptEncryption
    equals: false
'''),
        throwsConfigAt(contains('non-empty `reason`'), 3),
      );
    });

    test('an unknown or missing file is an error', () {
      expect(
        () => parse('''
checks:
  pin:
    file: build_gradle
    key: minSdk
    equals: 24
    reason: x
'''),
        throwsConfigAt(
          'unknown file `build_gradle` in `checks.pin`; expected one of '
          'info_plist, android_manifest',
          3,
        ),
      );
      expect(
        () => parse('checks:\n  pin:\n    key: A\n    exists: true\n'),
        throwsConfigAt(contains('needs `file`'), 3),
      );
    });

    test('an unknown operator is an error that lists the operators', () {
      expect(
        () => parse('''
checks:
  pin:
    file: info_plist
    key: CFBundleVersion
    greater_than: 3
    reason: x
'''),
        throwsConfigAt(
          allOf(contains('unknown key `greater_than`'), contains('none_of')),
          5,
        ),
      );
    });

    test('exactly one operator per check', () {
      expect(
        () => parse('''
checks:
  pin:
    file: info_plist
    key: CFBundleVersion
    reason: x
'''),
        throwsConfigAt(contains('needs one of exists, absent, equals'), 3),
      );
      expect(
        () => parse('''
checks:
  pin:
    file: info_plist
    key: CFBundleVersion
    exists: true
    matches: x
    reason: x
'''),
        throwsConfigAt(contains('has `exists` and `matches`'), 3),
      );
    });

    test('keys of the other file kind are errors', () {
      expect(
        () => parse('''
checks:
  pin:
    file: android_manifest
    key: android:allowBackup
    exists: true
    reason: x
'''),
        throwsConfigAt(contains('unknown key `key`'), 4),
      );
      expect(
        () => parse('''
checks:
  pin:
    file: android_manifest
    element: application
    exists: true
    reason: x
'''),
        throwsConfigAt(contains('needs `element` and `attribute`'), 3),
      );
      expect(
        () => parse('''
checks:
  pin:
    file: info_plist
    exists: true
    reason: x
'''),
        throwsConfigAt(contains('needs `key`'), 3),
      );
    });

    test('wrong value types are errors with the value line', () {
      String check(String file, String rest) =>
          'checks:\n  pin:\n    file: $file\n    reason: x\n$rest';
      String plistCheck(String op) => check('info_plist', '    key: K\n$op');
      String manifestCheck(String op) => check(
        'android_manifest',
        '    element: application\n    attribute: android:allowBackup\n$op',
      );
      expect(
        () => parse(manifestCheck('    equals: false\n')),
        throwsConfigAt(contains('write `"false"`, not `false`'), 7),
      );
      expect(
        () => parse(manifestCheck('    equals: [a, b]\n')),
        throwsConfigAt(contains('use `contains` or `none_of`'), 7),
      );
      expect(
        () => parse(plistCheck('    equals: {a: 1}\n')),
        throwsConfigAt(contains('a string, boolean or number'), 6),
      );
      expect(
        () => parse(plistCheck('    equals:\n')),
        throwsConfigAt(contains('a string, boolean or number'), 6),
      );
      expect(
        () => parse(plistCheck('    equals: [a, [b]]\n')),
        throwsConfigAt(contains('a string, boolean or number'), 6),
      );
      expect(
        () => parse(plistCheck('    contains: []\n')),
        throwsConfigAt(contains('at least one value'), 6),
      );
      expect(
        () => parse(plistCheck('    exists: false\n')),
        throwsConfigAt(contains('use `absent: true`'), 6),
      );
      expect(
        () => parse(plistCheck('    matches: 3\n')),
        throwsConfigAt(contains('a regular expression'), 6),
      );
      expect(
        () => parse(plistCheck('    matches: "("\n')),
        throwsConfigAt(contains('not a valid regular expression'), 6),
      );
      expect(
        () => parse(check('info_plist', '    key: A..B\n    exists: true\n')),
        throwsConfigAt(contains('empty part'), 5),
      );
      expect(
        () => parse(check('info_plist', '    key: {A: B}\n    exists: true\n')),
        throwsConfigAt(contains('a string or a list of strings'), 5),
      );
    });

    test('check names are kebab-case and checks is a map', () {
      expect(
        () => parse('checks:\n  No_Backup:\n    file: info_plist\n'),
        throwsConfigAt(contains('must be kebab-case'), 2),
      );
      expect(
        () => parse('checks:\n  - pin\n'),
        throwsConfigAt(contains('`checks` must be a map'), 2),
      );
      expect(
        () => parse('checks:\n  pin: true\n'),
        throwsConfigAt(contains('`checks.pin` must be a map'), 2),
      );
    });
  });

  group('IgnoreEntry.matches', () {
    const finding = Finding(
      ruleId: 'alpha',
      severity: Severity.warning,
      message: 'No entitlements file declares `aps-environment`',
      path: 'ios/Runner/Info.plist',
    );

    test('by rule, path, directory prefix and message text', () {
      expect(
        const IgnoreEntry(rule: 'alpha', reason: 'r').matches(finding),
        isTrue,
      );
      expect(
        const IgnoreEntry(rule: 'other', reason: 'r').matches(finding),
        isFalse,
      );
      expect(
        const IgnoreEntry(
          rule: 'alpha',
          reason: 'r',
          path: 'ios/',
        ).matches(finding),
        isTrue,
      );
      expect(
        const IgnoreEntry(
          rule: 'alpha',
          reason: 'r',
          path: 'ios/Runner',
        ).matches(finding),
        isFalse,
      );
      expect(
        const IgnoreEntry(
          rule: 'alpha',
          reason: 'r',
          match: 'aps-environment',
        ).matches(finding),
        isTrue,
      );
    });
  });
}
