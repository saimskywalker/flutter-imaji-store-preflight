import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:storehound/storehound.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const fixture = 'test/fixtures/production_app';
const golden = 'test/fixtures/production_app.golden.txt';

/// Copies the fixture to a temporary directory, applies [edits] (path to a
/// function of the file's text), and returns the run's findings.
List<Finding> runMutated(Map<String, String Function(String)> edits) {
  final dir = Directory.systemTemp.createTempSync('isp_production_');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final file in Directory(fixture).listSync(recursive: true)) {
    if (file is! File) continue;
    final relative = p.relative(file.path, from: fixture);
    final copy = File(p.join(dir.path, relative))
      ..parent.createSync(recursive: true);
    file.copySync(copy.path);
  }
  for (final MapEntry(key: path, value: edit) in edits.entries) {
    final file = File(p.join(dir.path, path));
    final before = file.existsSync() ? file.readAsStringSync() : '';
    final after = edit(before);
    expect(after, isNot(before), reason: 'the edit to $path changed nothing');
    file.writeAsStringSync(after);
  }
  final config = PreflightConfig.load(
    p.join(dir.path, configFileName),
    builtInRules,
  );
  return runPreflight(dir.path, config: config, today: fixedToday).findings;
}

/// Replaces exactly one occurrence of [from].
String Function(String) replace(String from, String to) => (text) {
  expect(from.allMatches(text), hasLength(1), reason: from);
  return text.replaceFirst(from, to);
};

void main() {
  test('the production-shaped fixture has no findings (golden)', () {
    final out = StringBuffer();
    final code = runCli(
      [
        '--project',
        fixture,
        '--today',
        '2026-10-01',
        '--fail-on',
        'info',
        '--brief',
        '--no-color',
      ],
      stdoutSink: out,
      stderrSink: StringBuffer(),
      workingDir: Directory.current.path,
      environment: const {},
    );
    expect(out.toString(), File(golden).readAsStringSync());
    expect(code, ExitCodes.ok, reason: out.toString());
  });

  test('a run on the fixture takes well under 2 seconds', () {
    final config = PreflightConfig.load(
      p.join(fixture, configFileName),
      builtInRules,
    );
    final watch = Stopwatch()..start();
    runPreflight(fixture, config: config, today: fixedToday);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  group('one mutation per rule is still caught', () {
    const info = 'ios/Runner/Info.plist';
    const manifest = 'android/app/src/main/AndroidManifest.xml';

    test('Release entitlements without aps-environment', () {
      expect(
        runMutated({
          'ios/Runner/RunnerRelease.entitlements': replace(
            '\t<key>aps-environment</key>\n\t<string>production</string>\n',
            '',
          ),
        }),
        [
          isFinding(
            path: 'ios/Runner/RunnerRelease.entitlements',
            message: contains('Release'),
          ),
        ],
      );
    });

    test('a purpose string a plugin needs is deleted', () {
      expect(
        runMutated({
          info: replace(
            '<key>NSFaceIDUsageDescription</key>',
            '<key>NSFaceIDUsageDescription_removed</key>',
          ),
        }),
        [isFinding(message: contains('local_auth needs it'))],
      );
    });

    test('a key only a linked SDK references is deleted', () {
      expect(
        runMutated({
          info: replace(
            '<key>NSLocationWhenInUseUsageDescription</key>',
            '<key>NSLocationWhenInUseUsageDescription_removed</key>',
          ),
        }),
        [isFinding(message: contains('acme_payments references'))],
      );
    });

    test('a purpose string loses its example', () {
      expect(
        runMutated({
          info: replace(
            ', for example the code on a shelf label in one of our stores.',
            '.',
          ),
        }),
        [isFinding(message: contains('gives no example'))],
      );
    });

    test('a background mode without a justification', () {
      expect(
        runMutated({
          info: replace(
            '\t\t<string>remote-notification</string>\n',
            '\t\t<string>remote-notification</string>\n'
                '\t\t<string>fetch</string>\n',
          ),
        }),
        [isFinding(message: contains('`fetch`'))],
      );
    });

    test('an ARB locale that CFBundleLocalizations does not list', () {
      expect(
        runMutated({'lib/l10n/arb/app_de.arb': (_) => '{"@@locale": "de"}\n'}),
        [isFinding(message: contains('`de`'))],
      );
    });

    test('the privacy manifest drops out of Copy Bundle Resources', () {
      expect(
        runMutated({
          'ios/Runner.xcodeproj/project.pbxproj': (text) =>
              text.replaceAll('PrivacyInfo.xcprivacy in Resources', 'x'),
        }),
        [isFinding(message: contains('Copy Bundle Resources'))],
      );
    });

    test('collected data that a linked SDK needs is removed', () {
      expect(
        runMutated({
          'ios/Runner/PrivacyInfo.xcprivacy': replace(
            'NSPrivacyCollectedDataTypeCrashData',
            'NSPrivacyCollectedDataTypeOtherDiagnosticData',
          ),
        }),
        [isFinding(message: contains('firebase_crashlytics'))],
      );
    });

    test('ExportOptions lets Xcode renumber the build', () {
      expect(
        runMutated({
          'ios/ExportOptions-appstore.plist': replace(
            '<key>manageAppVersionAndBuildNumber</key>\n\t<false/>',
            '<key>manageAppVersionAndBuildNumber</key>\n\t<true/>',
          ),
        }),
        [isFinding(path: 'ios/ExportOptions-appstore.plist')],
      );
    });

    test('the OPEN_DOCUMENT query is removed, GET_CONTENT stays', () {
      expect(
        runMutated({
          manifest: replace('intent.action.OPEN_DOCUMENT', 'intent.action.X'),
        }),
        [isFinding(message: contains('OPEN_DOCUMENT'))],
      );
    });

    test('targetSdk falls below the Play deadline', () {
      expect(
        runMutated({
          'android/app/build.gradle.kts': replace(
            '        targetSdk = 36',
            '        targetSdk = 35',
          ),
        }),
        [isFinding(line: 36, message: contains('targetSdk is 35'))],
      );
    });
  });
}
