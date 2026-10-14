import 'package:imaji_store_preflight/imaji_store_preflight.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

class _AlwaysFinds extends Rule {
  const _AlwaysFinds();

  @override
  String get id => 'always-finds';
  @override
  String get title => 'Test rule';
  @override
  RulePlatform get platform => RulePlatform.general;
  @override
  Severity get defaultSeverity => Severity.warning;
  @override
  String get why => 'Because tests need a rule.';
  @override
  String get fix => 'Nothing.';
  @override
  List<String> get docs => const ['https://example.com'];

  @override
  Iterable<Finding> check(RuleContext context) => [
    finding('first', path: 'a.txt', line: 1),
    finding('second', path: 'b.txt'),
  ];
}

void main() {
  const rule = _AlwaysFinds();

  test('runs rules and reports findings in order', () {
    final report = runPreflight(writeProject({}), rules: [rule]);
    expect(report.findings.map((f) => f.message), ['first', 'second']);
    expect(report.count(Severity.warning), 2);
    expect(report.failed, isFalse, reason: 'default threshold is error');
  });

  test('a severity override applies to every finding of the rule', () {
    final report = runPreflight(
      writeProject({}),
      rules: [rule],
      config: const PreflightConfig(
        rules: {'always-finds': RuleConfig(severity: Severity.error)},
      ),
    );
    expect(report.count(Severity.error), 2);
    expect(report.failed, isTrue);
  });

  test('fail_on decides failure', () {
    PreflightReport run(Severity? failOn) => runPreflight(
      writeProject({}),
      rules: [rule],
      config: PreflightConfig(failOn: failOn),
    );
    expect(run(Severity.warning).failed, isTrue);
    expect(run(Severity.info).failed, isTrue);
    expect(run(Severity.error).failed, isFalse);
    expect(run(null).failed, isFalse);
  });

  test('disabled rules do not run and are listed with their reason', () {
    final report = runPreflight(
      writeProject({}),
      rules: [rule],
      config: const PreflightConfig(
        rules: {'always-finds': RuleConfig(enabled: false, reason: 'why not')},
      ),
    );
    expect(report.findings, isEmpty);
    expect(report.rules, isEmpty);
    expect(report.disabled.single.reason, 'why not');
    expect(report.ruleById('always-finds'), same(rule));
  });

  test(
    'ignore entries suppress matching findings and unused ones are listed',
    () {
      const used = IgnoreEntry(
        rule: 'always-finds',
        reason: 'ok',
        path: 'a.txt',
      );
      const unused = IgnoreEntry(
        rule: 'always-finds',
        reason: 'old',
        match: 'zzz',
      );
      final report = runPreflight(
        writeProject({}),
        rules: [rule],
        config: const PreflightConfig(ignores: [used, unused]),
      );
      expect(report.findings.map((f) => f.message), ['second']);
      expect(report.suppressed.single.finding.message, 'first');
      expect(report.suppressed.single.entry, same(used));
      expect(report.unusedIgnores, [unused]);
    },
  );

  test('unreadable files become findings of the unreadable-file rule', () {
    final report = runPreflight(
      writeProject({
        'ios/Runner/Info.plist': 'bplist00 binary bytes',
        'android/app/src/main/AndroidManifest.xml': '<manifest><application>',
      }),
    );
    final unreadable = report.findings
        .where((f) => f.ruleId == 'unreadable-file')
        .toList();
    expect(unreadable, hasLength(2));
    expect(unreadable.first.message, contains('binary property list'));
    expect(unreadable.last.path, 'android/app/src/main/AndroidManifest.xml');
  });

  test('a clean minimal project has no findings', () {
    final report = runPreflight(
      writeProject({
        'ios/Runner/Info.plist': infoPlist(),
        'ios/Runner/PrivacyInfo.xcprivacy': plist('''
  <key>NSPrivacyTracking</key>
  <false/>'''),
      }),
      today: fixedToday,
    );
    expect(report.findings, isEmpty);
  });
}
