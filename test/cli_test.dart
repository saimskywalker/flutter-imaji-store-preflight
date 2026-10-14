import 'dart:convert';
import 'dart:io';

import 'package:imaji_store_preflight/imaji_store_preflight.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixtures.dart';

class CliResult {
  CliResult(this.code, this.out, this.err);
  final int code;
  final String out;
  final String err;
}

CliResult run(List<String> args, {String? cwd}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = runCli(
    ['--today', '2026-10-01', ...args],
    stdoutSink: out,
    stderrSink: err,
    workingDir: cwd ?? Directory.current.path,
    environment: const {},
  );
  return CliResult(code, out.toString(), err.toString());
}

const rejected = 'test/fixtures/rejected_app';
const clean = 'test/fixtures/clean_app';

void main() {
  test('a clean project exits 0', () {
    final result = run(['--project', clean]);
    expect(result.out, contains('✓'));
    expect(result.code, ExitCodes.ok, reason: result.out);
  });

  test('a project with errors exits 1 and explains each rule', () {
    final result = run([rejected]);
    expect(result.code, ExitCodes.findings);
    final out = result.out;
    for (final id in [
      'privacy-manifest-sdk-data',
      'tracking-usage-description',
      'purpose-string-missing',
      'purpose-string-quality',
      'background-modes-justified',
      'export-options-build-number',
      'bundle-localizations',
      'android-picker-queries',
      'android-target-sdk',
    ]) {
      expect(out, contains(id), reason: id);
    }
    expect(out, contains('why: '));
    expect(out, contains('fix: '));
    expect(
      out,
      contains('$rejected/ios/Runner/Info.plist:13'),
      reason: 'paths are shown relative to the working directory',
    );
    expect(out, contains('Suppressed by `ignore`'));
    expect(out, contains('Wording approved'));
    expect(out, contains('Disabled rules'));
    expect(out, contains('push-entitlement  — The fixture has no push'));
    expect(out, isNot(contains('\x1B[')), reason: 'no colour when piped');
  });

  test('--brief drops the explanations', () {
    final out = run([rejected, '--brief']).out;
    expect(out, isNot(contains('why: ')));
  });

  test('--fail-on never exits 0 even with errors', () {
    expect(run([rejected, '--fail-on', 'never']).code, ExitCodes.ok);
  });

  test('--fail-on warning fails on warnings alone', () {
    final root = writeProject({'ios/Runner/Info.plist': infoPlist()});
    expect(run([root]).code, ExitCodes.ok);
    expect(run([root, '--fail-on', 'warning']).code, ExitCodes.findings);
  });

  test('json output is machine readable', () {
    final result = run([rejected, '--format', 'json']);
    expect(result.code, ExitCodes.findings);
    final json = jsonDecode(result.out) as Map<String, Object?>;
    expect(json['schemaVersion'], 1);
    expect(json['failed'], isTrue);
    final findings = (json['findings'] as List).cast<Map<String, Object?>>();
    expect(
      findings.map((f) => f['rule']),
      contains('export-options-build-number'),
    );
    final exportFinding = findings.firstWhere(
      (f) => f['rule'] == 'export-options-build-number',
    );
    expect(exportFinding['path'], '$rejected/ios/ExportOptions.plist');
    expect(exportFinding['line'], 7);
    expect(
      (json['suppressed'] as List).single,
      containsPair('reason', isNotEmpty),
    );
    expect(json['disabledRules'], [
      {
        'rule': 'push-entitlement',
        'reason': 'The fixture has no push feature.',
      },
    ]);
  });

  test('--output writes the report to a file and summarises on stderr', () {
    final dir = Directory.systemTemp.createTempSync('isp_out_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = p.join(dir.path, 'nested', 'report.json');
    final result = run([rejected, '-f', 'json', '-o', path]);
    expect(result.out, isEmpty);
    expect(result.err, contains('report written to'));
    expect(
      jsonDecode(File(path).readAsStringSync()),
      isA<Map<String, Object?>>(),
    );
  });

  test('--list-rules and --explain', () {
    final list = run(['--list-rules']);
    expect(list.code, ExitCodes.ok);
    for (final rule in builtInRules) {
      expect(list.out, contains(rule.id));
    }
    final explain = run(['--explain', 'android-picker-queries']);
    expect(explain.out, contains('Why it matters'));
    expect(explain.out, contains('OPEN_DOCUMENT'));
    expect(run(['--explain', 'nope']).code, ExitCodes.usage);
  });

  test('--version and --help', () {
    expect(run(['--version']).out.trim(), '$packageName $packageVersion');
    final help = run(['--help']);
    expect(help.code, ExitCodes.ok);
    expect(help.out, contains('Exit codes'));
  });

  test('usage errors exit 2', () {
    expect(run(['--format', 'xml']).code, ExitCodes.usage);
    expect(run(['--project', 'does/not/exist']).code, ExitCodes.usage);
    expect(run(['--today', 'yesterday', clean]).code, ExitCodes.usage);
    expect(run(['a', 'b']).code, ExitCodes.usage);
    final empty = Directory.systemTemp.createTempSync('isp_empty_');
    addTearDown(() => empty.deleteSync(recursive: true));
    final notFlutter = run([empty.path]);
    expect(notFlutter.code, ExitCodes.usage);
    expect(notFlutter.err, contains('pubspec.yaml'));
  });

  test('an invalid configuration exits 2 with the reason', () {
    final root = writeProject({
      'imaji_store_preflight.yaml':
          'rules:\n  bundle-localizations:\n    enabled: false\n',
    });
    final result = run([root]);
    expect(result.code, ExitCodes.usage);
    expect(result.err, contains('reason'));
    expect(result.err, contains('imaji_store_preflight.yaml:3'));
  });

  test('--config points at a configuration elsewhere', () {
    final dir = Directory.systemTemp.createTempSync('isp_cfg_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final config = File(p.join(dir.path, 'strict.yaml'))
      ..writeAsStringSync('fail_on: never\n');
    expect(run([rejected, '--config', config.path]).code, ExitCodes.ok);
    expect(
      run([rejected, '--config', p.join(dir.path, 'missing.yaml')]).code,
      ExitCodes.usage,
    );
  });

  test('the executable runs end to end', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/imaji_store_preflight.dart',
      '--today',
      '2026-10-01',
      clean,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
