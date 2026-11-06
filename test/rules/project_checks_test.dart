import 'dart:convert';

import 'package:storehound/storehound.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

const info = 'ios/Runner/Info.plist';
const manifestPath = 'android/app/src/main/AndroidManifest.xml';

/// Runs only the project checks in [config] (a `storehound.yaml` body)
/// against a project built from [files].
PreflightReport runChecks(String config, Map<String, String> files) {
  final root = writeProject(files);
  return runPreflight(
    root,
    rules: const [],
    config: PreflightConfig.parse(config, builtInRules),
    today: fixedToday,
  );
}

List<Finding> findings(String config, Map<String, String> files) =>
    runChecks(config, files).findings;

/// One Info.plist check named `pin` with [body] as its key and operator.
String plistCheck(String body) =>
    '''
checks:
  pin:
    file: info_plist
    reason: Pinned on purpose.
$body
''';

/// One AndroidManifest check named `pin` on [element] / [attribute].
String manifestCheck(String element, String attribute, String body) =>
    '''
checks:
  pin:
    file: android_manifest
    element: $element
    attribute: $attribute
    reason: Pinned on purpose.
$body
''';

/// The 1-based line of the first line of [text] containing [needle].
int lineIn(String text, String needle) {
  final lines = const LineSplitter().convert(text);
  final i = lines.indexWhere((l) => l.contains(needle));
  if (i < 0) throw StateError('no line contains $needle');
  return i + 1;
}

final encryption = infoPlist('''
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  <key>UIBackgroundModes</key>
  <array>
    <string>audio</string>
    <string>remote-notification</string>
  </array>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoadsInWebContent</key>
    <true/>
    <key>NSExceptionDomains</key>
    <dict>
      <key>example.com</key>
      <dict>
        <key>NSIncludesSubdomains</key>
        <true/>
      </dict>
    </dict>
  </dict>
  <key>CFBundleVersion</key>
  <string>42</string>
  <key>UIRequiredDeviceCapabilities</key>
  <integer>7</integer>''');

/// The `<dict>` line of an [infoPlist] fixture.
final rootDictLine = lineIn(encryption, '<dict>');

final manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <application
        android:label="fixture"
        android:allowBackup="false">
        <activity android:name=".MainActivity" android:exported="true" />
    </application>
</manifest>
''';

void main() {
  group('info_plist', () {
    Map<String, String> files() => {info: encryption};

    test('exists: passes when present, reports the parent line when '
        'missing', () {
      expect(
        findings(
          plistCheck('    key: CFBundleVersion\n    exists: true'),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          plistCheck('    key: CFBundleName\n    exists: true'),
          files(),
        ),
        [
          isFinding(
            message: '`CFBundleName` is missing.',
            path: info,
            line: rootDictLine,
            severity: Severity.error,
          ),
        ],
      );
    });

    test('absent: reports the key line when present', () {
      expect(
        findings(
          plistCheck('    key: NSAllowsArbitraryLoads\n    absent: true'),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          plistCheck(
            '    key: ITSAppUsesNonExemptEncryption\n    absent: true',
          ),
          files(),
        ),
        [
          isFinding(
            message:
                '`ITSAppUsesNonExemptEncryption` is present (false); '
                'expected it to be absent.',
            line: lineIn(encryption, 'ITSAppUsesNonExemptEncryption'),
          ),
        ],
      );
    });

    test('equals: a boolean, a string and a number', () {
      expect(
        findings(
          plistCheck(
            '    key: ITSAppUsesNonExemptEncryption\n    equals: false',
          ),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          plistCheck('    key: CFBundleVersion\n    equals: "42"'),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          plistCheck('    key: UIRequiredDeviceCapabilities\n    equals: 7'),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          plistCheck(
            '    key: ITSAppUsesNonExemptEncryption\n    equals: true',
          ),
          files(),
        ),
        [
          isFinding(
            message: '`ITSAppUsesNonExemptEncryption` is false; expected true.',
            line: lineIn(encryption, 'ITSAppUsesNonExemptEncryption'),
          ),
        ],
      );
    });

    test('equals: types must match, so the string "42" is not 42', () {
      expect(
        findings(
          plistCheck('    key: CFBundleVersion\n    equals: 42'),
          files(),
        ),
        [isFinding(message: '`CFBundleVersion` is "42"; expected 42.')],
      );
    });

    test('equals: a missing key is reported at the parent', () {
      expect(
        findings(
          plistCheck('    key: LSRequiresIPhoneOS\n    equals: true'),
          files(),
        ),
        [
          isFinding(
            message: '`LSRequiresIPhoneOS` is missing; expected true.',
            line: rootDictLine,
          ),
        ],
      );
    });

    test('equals: a list is the same items in any order', () {
      expect(
        findings(
          plistCheck(
            '    key: UIBackgroundModes\n'
            '    equals: [remote-notification, audio]',
          ),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          plistCheck('    key: UIBackgroundModes\n    equals: [audio]'),
          files(),
        ),
        [
          isFinding(
            message:
                '`UIBackgroundModes` is ["audio", "remote-notification"]; '
                'expected ["audio"].',
            line: lineIn(encryption, 'UIBackgroundModes'),
          ),
        ],
      );
    });

    test('a dotted key reads nested dictionaries; a missing nested key is '
        'reported at its parent key', () {
      expect(
        findings(
          plistCheck(
            '    key: NSAppTransportSecurity.NSAllowsArbitraryLoadsInWebContent\n'
            '    equals: true',
          ),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          plistCheck(
            '    key: NSAppTransportSecurity.NSAllowsArbitraryLoads\n'
            '    equals: false',
          ),
          files(),
        ),
        [
          isFinding(
            message:
                '`NSAppTransportSecurity.NSAllowsArbitraryLoads` is '
                'missing; expected false.',
            line: lineIn(encryption, '<key>NSAppTransportSecurity'),
          ),
        ],
      );
    });

    test('a key given as a list takes each part literally, dots included', () {
      expect(
        findings(
          plistCheck(
            '    key: [NSAppTransportSecurity, NSExceptionDomains, example.com,'
            ' NSIncludesSubdomains]\n'
            '    equals: true',
          ),
          files(),
        ),
        isEmpty,
      );
    });

    test('a path through a value that is not a dictionary is missing', () {
      expect(
        findings(
          plistCheck('    key: CFBundleVersion.Major\n    exists: true'),
          files(),
        ),
        [
          isFinding(
            message: '`CFBundleVersion.Major` is missing.',
            line: lineIn(encryption, 'CFBundleVersion'),
          ),
        ],
      );
    });

    test(
      'absent_or_equals: absent or equal passes, a different value fails',
      () {
        const key = 'NSAppTransportSecurity.NSAllowsArbitraryLoads';
        expect(
          findings(
            plistCheck('    key: $key\n    absent_or_equals: false'),
            files(),
          ),
          isEmpty,
        );
        expect(
          findings(
            plistCheck(
              '    key: ITSAppUsesNonExemptEncryption\n'
              '    absent_or_equals: false',
            ),
            files(),
          ),
          isEmpty,
        );
        expect(
          findings(
            plistCheck(
              '    key: ITSAppUsesNonExemptEncryption\n'
              '    absent_or_equals: true',
            ),
            files(),
          ),
          [isFinding(message: contains('is false; expected true'))],
        );
      },
    );

    test(
      'not_equals: absent or different passes, the forbidden value fails',
      () {
        expect(
          findings(
            plistCheck('    key: CFBundleName\n    not_equals: x'),
            files(),
          ),
          isEmpty,
        );
        expect(
          findings(
            plistCheck('    key: CFBundleVersion\n    not_equals: "1"'),
            files(),
          ),
          isEmpty,
        );
        expect(
          findings(
            plistCheck('    key: CFBundleVersion\n    not_equals: "42"'),
            files(),
          ),
          [
            isFinding(
              message: '`CFBundleVersion` is "42", which this check forbids.',
              line: lineIn(encryption, 'CFBundleVersion'),
            ),
          ],
        );
      },
    );

    test('contains: one finding per value the array lacks', () {
      expect(
        findings(
          plistCheck('    key: UIBackgroundModes\n    contains: audio'),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          plistCheck(
            '    key: UIBackgroundModes\n    contains: [audio, fetch, processing]',
          ),
          files(),
        ),
        [
          isFinding(message: '`UIBackgroundModes` does not contain "fetch".'),
          isFinding(
            message: '`UIBackgroundModes` does not contain "processing".',
            line: lineIn(encryption, 'UIBackgroundModes'),
          ),
        ],
      );
    });

    test('contains: a missing key or a value that is not an array fails', () {
      expect(
        findings(
          plistCheck('    key: CFBundleLocalizations\n    contains: [en]'),
          files(),
        ),
        [
          isFinding(
            message: contains('is missing; expected an array containing "en"'),
          ),
        ],
      );
      expect(
        findings(
          plistCheck('    key: CFBundleVersion\n    contains: [x]'),
          files(),
        ),
        [isFinding(message: '`CFBundleVersion` is "42", not an array.')],
      );
    });

    test('none_of: reports each forbidden array item on its own line', () {
      expect(
        findings(
          plistCheck(
            '    key: UIBackgroundModes\n    none_of: [fetch, location]',
          ),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          plistCheck('    key: CFBundleName\n    none_of: [x]'),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          plistCheck(
            '    key: UIBackgroundModes\n    none_of: [remote-notification]',
          ),
          files(),
        ),
        [
          isFinding(
            message:
                '`UIBackgroundModes` contains "remote-notification", '
                'which this check forbids.',
            line: lineIn(encryption, '<string>remote-notification'),
          ),
        ],
      );
      expect(
        findings(
          plistCheck('    key: CFBundleVersion\n    none_of: ["42"]'),
          files(),
        ),
        [
          isFinding(
            message: '`CFBundleVersion` is "42", which this check forbids.',
          ),
        ],
      );
    });

    test('matches: a regular expression on a string value', () {
      expect(
        findings(
          plistCheck(
            '    key: CFBundleIdentifier\n'
            r"    matches: '^com\.example\.'",
          ),
          {info: infoPlist()},
        ),
        isEmpty,
      );
      expect(
        findings(
          plistCheck(
            '    key: CFBundleVersion\n'
            r"    matches: '^\d+\.\d+$'",
          ),
          files(),
        ),
        [
          isFinding(
            message:
                r'`CFBundleVersion` is "42", which does not match /^\d+\.\d+$/.',
          ),
        ],
      );
      expect(
        findings(
          plistCheck('    key: UIBackgroundModes\n    matches: audio'),
          files(),
        ),
        [
          isFinding(
            message:
                '`UIBackgroundModes` is ["audio", "remote-notification"], '
                'not a string.',
          ),
        ],
      );
      expect(
        findings(plistCheck('    key: CFBundleName\n    matches: x'), files()),
        [
          isFinding(
            message:
                '`CFBundleName` is missing; expected a string matching /x/.',
          ),
        ],
      );
    });

    test('paths.info_plist moves the file the check reads', () {
      expect(
        findings(
          'paths:\n  info_plist: app/Info.plist\n'
          '${plistCheck('    key: ITSAppUsesNonExemptEncryption\n    equals: false')}',
          {'app/Info.plist': encryption},
        ),
        isEmpty,
      );
    });

    test('a missing file is a finding, an unreadable one is left to '
        'unreadable-file', () {
      final check = plistCheck('    key: CFBundleVersion\n    exists: true');
      expect(findings(check, {}), [
        isFinding(message: contains('ios/Runner/Info.plist does not exist')),
      ]);
      expect(findings(check, {info: '<plist><dict>'}), isEmpty);
    });
  });

  group('android_manifest', () {
    Map<String, String> files() => {manifestPath: manifest};
    final backupLine = lineIn(manifest, 'android:allowBackup');
    final applicationLine = lineIn(manifest, '<application');

    test('equals: passes, and reports the attribute line when different', () {
      expect(
        findings(
          manifestCheck(
            'application',
            'android:allowBackup',
            '    equals: "false"',
          ),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          manifestCheck(
            'application',
            'android:allowBackup',
            '    equals: "true"',
          ),
          files(),
        ),
        [
          isFinding(
            message:
                '<application> has android:allowBackup="false"; '
                'expected "true".',
            path: manifestPath,
            line: backupLine,
          ),
        ],
      );
    });

    test('equals: a missing attribute is reported at its element', () {
      expect(
        findings(
          manifestCheck(
            'application',
            'android:fullBackupContent',
            '    equals: "false"',
          ),
          files(),
        ),
        [
          isFinding(
            message:
                '<application> has no android:fullBackupContent; '
                'expected "false".',
            line: applicationLine,
          ),
        ],
      );
    });

    test('a missing element is reported at the root element', () {
      expect(
        findings(
          manifestCheck('queries', 'android:name', '    exists: true'),
          files(),
        ),
        [
          isFinding(
            message: contains('The manifest has no <queries> element'),
            line: lineIn(manifest, '<manifest'),
          ),
        ],
      );
      expect(
        findings(
          manifestCheck('queries', 'android:name', '    absent: true'),
          files(),
        ),
        isEmpty,
      );
    });

    test('exists and absent', () {
      expect(
        findings(
          manifestCheck('activity', 'android:exported', '    exists: true'),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          manifestCheck('activity', 'android:theme', '    exists: true'),
          files(),
        ),
        [isFinding(message: 'No <activity> sets android:theme.')],
      );
      expect(
        findings(
          manifestCheck(
            'application',
            'android:debuggable',
            '    absent: true',
          ),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          manifestCheck('application', 'android:label', '    absent: true'),
          files(),
        ),
        [
          isFinding(
            message:
                '<application> has android:label="fixture"; '
                'expected it to be absent.',
            line: lineIn(manifest, 'android:label'),
          ),
        ],
      );
    });

    test('absent_or_equals and not_equals', () {
      expect(
        findings(
          manifestCheck(
            'application',
            'android:usesCleartextTraffic',
            '    absent_or_equals: "false"',
          ),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          manifestCheck(
            'application',
            'android:allowBackup',
            '    absent_or_equals: "true"',
          ),
          files(),
        ),
        [isFinding(message: contains('expected "true"'), line: backupLine)],
      );
      expect(
        findings(
          manifestCheck(
            'activity',
            'android:exported',
            '    not_equals: "false"',
          ),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          manifestCheck(
            'activity',
            'android:exported',
            '    not_equals: "true"',
          ),
          files(),
        ),
        [
          isFinding(
            message:
                '<activity> has android:exported="true", which this check '
                'forbids.',
            line: lineIn(manifest, '<activity'),
          ),
        ],
      );
    });

    test('contains: across every matching element, missing values at the '
        'parent', () {
      expect(
        findings(
          manifestCheck(
            'uses-permission',
            'android:name',
            '    contains: [android.permission.INTERNET, android.permission.CAMERA]',
          ),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          manifestCheck(
            'uses-permission',
            'android:name',
            '    contains: android.permission.POST_NOTIFICATIONS',
          ),
          files(),
        ),
        [
          isFinding(
            message:
                'No <uses-permission> has '
                'android:name="android.permission.POST_NOTIFICATIONS".',
            line: lineIn(manifest, '<manifest'),
          ),
        ],
      );
    });

    test('none_of: one finding per forbidden element', () {
      final check = manifestCheck(
        'uses-permission',
        'android:name',
        '    none_of:\n'
            '      - android.permission.READ_MEDIA_IMAGES\n'
            '      - android.permission.CAMERA',
      );
      expect(findings(check, files()), [
        isFinding(
          message:
              '<uses-permission> has android:name='
              '"android.permission.CAMERA", which this check forbids.',
          line: lineIn(manifest, 'permission.CAMERA'),
        ),
      ]);
    });

    test('matches', () {
      expect(
        findings(
          manifestCheck('activity', 'android:name', r"    matches: '^\.'"),
          files(),
        ),
        isEmpty,
      );
      expect(
        findings(
          manifestCheck('application', 'android:label', '    matches: ^Acme'),
          files(),
        ),
        [
          isFinding(
            message:
                '<application> has android:label="fixture", which does '
                'not match /^Acme/.',
          ),
        ],
      );
      expect(
        findings(
          manifestCheck('application', 'android:icon', '    matches: x'),
          files(),
        ),
        [
          isFinding(
            message: contains('has no android:icon'),
            line: applicationLine,
          ),
        ],
      );
    });

    test('a missing manifest is a finding', () {
      expect(
        findings(
          manifestCheck(
            'application',
            'android:allowBackup',
            '    exists: true',
          ),
          {},
        ),
        [isFinding(message: contains('paths.android_manifest'))],
      );
    });
  });

  group('like any rule', () {
    final config = '''
checks:
  no-backup:
    file: android_manifest
    element: application
    attribute: android:allowBackup
    equals: "true"
    reason: Restores keep the cart after a reinstall.
  encryption-exempt:
    file: info_plist
    key: ITSAppUsesNonExemptEncryption
    equals: true
    severity: warning
    reason: The app ships its own crypto and has an export compliance code.
''';
    Map<String, String> files() => {info: encryption, manifestPath: manifest};

    test('rule ids are check:<name>; severity defaults to error', () {
      expect(findings(config, files()).map((f) => (f.ruleId, f.severity)), [
        ('check:no-backup', Severity.error),
        ('check:encryption-exempt', Severity.warning),
      ]);
    });

    test('ignore suppresses a check and rules can change its severity', () {
      final report = runChecks('''
$config
rules:
  check:encryption-exempt:
    severity: info
ignore:
  - rule: check:no-backup
    reason: Backups are being switched back on in the next release.
''', files());
      expect(report.findings.single.ruleId, 'check:encryption-exempt');
      expect(report.findings.single.severity, Severity.info);
      expect(report.suppressed.single.finding.ruleId, 'check:no-backup');
    });

    test('text, JSON and SARIF report the check with its file and line', () {
      final report = runChecks(config, files());
      final text = renderText(report);
      expect(
        text,
        contains(
          'check:no-backup — <application android:allowBackup> equals "true"',
        ),
      );
      expect(
        text,
        contains('$manifestPath:${lineIn(manifest, 'allowBackup')}'),
      );
      expect(text, contains('why: Restores keep the cart'));

      final json = jsonDecode(renderJson(report)) as Map<String, Object?>;
      expect((json['findings']! as List).first, {
        'rule': 'check:no-backup',
        'severity': 'error',
        'message':
            '<application> has android:allowBackup="false"; '
            'expected "true".',
        'path': manifestPath,
        'line': lineIn(manifest, 'allowBackup'),
      });
      expect((json['rules']! as List).map((r) => (r as Map)['id']), [
        'check:no-backup',
        'check:encryption-exempt',
      ]);

      final sarif = jsonDecode(renderSarif(report)) as Map<String, Object?>;
      final run = (sarif['runs']! as List).single as Map<String, Object?>;
      final result = (run['results']! as List).last as Map<String, Object?>;
      expect(result['ruleId'], 'check:encryption-exempt');
      expect(result['level'], 'warning');
      expect(
        (((result['locations']! as List).single as Map)['physicalLocation']
            as Map)['region'],
        {'startLine': lineIn(encryption, 'ITSAppUsesNonExemptEncryption')},
      );
      final driver = (run['tool']! as Map)['driver']! as Map;
      final rule = (driver['rules']! as List).last as Map;
      expect(rule['id'], 'check:encryption-exempt');
      expect(rule['defaultConfiguration'], {'level': 'warning'});
      expect(rule.containsKey('helpUri'), isFalse);
    });

    test('explain shows the reason and the expected value', () {
      final check = PreflightConfig.parse(
        config,
        builtInRules,
      ).checkRules.first;
      final text = renderExplain(check);
      expect(text, startsWith('check:no-backup (error, android)'));
      expect(text, contains('Restores keep the cart'));
      expect(text, contains('android:allowBackup> equals "true"'));
    });
  });
}
