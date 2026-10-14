import 'package:imaji_store_preflight/imaji_store_preflight.dart';
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
