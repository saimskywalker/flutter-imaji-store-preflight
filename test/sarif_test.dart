import 'dart:convert';

import 'package:imaji_store_preflight/imaji_store_preflight.dart';
import 'package:test/test.dart';

void main() {
  late Map<String, Object?> sarif;
  late PreflightReport report;

  setUpAll(() {
    const root = 'test/fixtures/rejected_app';
    report = runPreflight(
      root,
      config: PreflightConfig.load('$root/$configFileName', builtInRules),
      today: DateTime.utc(2026, 10, 1),
      environment: const {},
    );
    sarif =
        jsonDecode(renderSarif(report, pathPrefix: root))
            as Map<String, Object?>;
  });

  Map<String, Object?> run() =>
      (sarif['runs'] as List).single as Map<String, Object?>;

  test('is SARIF 2.1.0 with the tool described', () {
    expect(sarif['version'], '2.1.0');
    expect(sarif[r'$schema'], contains('sarif-2.1.0'));
    final driver = (run()['tool'] as Map)['driver'] as Map;
    expect(driver['name'], packageName);
    expect(driver['version'], packageVersion);
    final rules = (driver['rules'] as List).cast<Map<String, Object?>>();
    expect(rules.map((r) => r['id']), report.rules.map((r) => r.id));
    for (final rule in rules) {
      expect(rule['helpUri'], startsWith('https://'));
      expect((rule['help'] as Map)['markdown'], contains('**How to fix.**'));
    }
  });

  test('results carry level, message and a repository-relative location', () {
    final results = (run()['results'] as List).cast<Map<String, Object?>>();
    expect(results.length, report.findings.length + report.suppressed.length);
    final export = results.firstWhere(
      (r) => r['ruleId'] == 'export-options-build-number',
    );
    expect(export['level'], 'error');
    final location =
        ((export['locations'] as List).single as Map)['physicalLocation']
            as Map;
    expect(location['artifactLocation'], {
      'uri': 'test/fixtures/rejected_app/ios/ExportOptions.plist',
      'uriBaseId': '%SRCROOT%',
    });
    expect(location['region'], {'startLine': 7});
    final ruleIndex = export['ruleIndex'] as int;
    final rules = ((run()['tool'] as Map)['driver'] as Map)['rules'] as List;
    expect((rules[ruleIndex] as Map)['id'], 'export-options-build-number');
  });

  test('warnings map to warning and info to note', () {
    final levels = {
      for (final r in (run()['results'] as List).cast<Map<String, Object?>>())
        r['level'],
    };
    expect(levels, containsAll(['error', 'warning']));
    expect(levels.difference({'error', 'warning', 'note'}), isEmpty);
  });

  test('suppressed findings carry their justification', () {
    final suppressed = (run()['results'] as List)
        .cast<Map<String, Object?>>()
        .where((r) => r.containsKey('suppressions'))
        .toList();
    expect(suppressed, hasLength(1));
    expect(suppressed.single['suppressions'], [
      {
        'kind': 'external',
        'justification': 'Wording approved in a previous review.',
      },
    ]);
  });
}
