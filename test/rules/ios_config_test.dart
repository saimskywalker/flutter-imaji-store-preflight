import 'package:imaji_store_preflight/imaji_store_preflight.dart';
import 'package:imaji_store_preflight/src/rules/ios_config.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

const info = 'ios/Runner/Info.plist';

String modes(List<String> values) =>
    '<key>UIBackgroundModes</key>\n  <array>\n'
    '${values.map((v) => '    <string>$v</string>').join('\n')}\n  </array>';

void main() {
  group('background-modes-justified', () {
    const rule = BackgroundModesRule();

    test('passes without background modes', () {
      expect(runRule(rule, {info: infoPlist()}), isEmpty);
    });

    test('passes allowlisted modes with a justification', () {
      expect(
        runRule(
          rule,
          {
            info: infoPlist(modes(['audio'])),
            'pubspec.lock': lockOf(['audio_service']),
          },
          options: {
            'allow': {
              'audio':
                  'Play any song, lock the device: playback continues and '
                  'the lock screen shows controls.',
            },
          },
        ),
        isEmpty,
      );
    });

    test('fails a mode nothing uses', () {
      expect(
        runRule(rule, {
          info: infoPlist(modes(['fetch'])),
        }),
        [
          isFinding(
            severity: Severity.error,
            message: contains('nothing linked'),
            line: isNotNull,
          ),
        ],
      );
    });

    test('warns about a plausibly used mode without a justification', () {
      expect(
        runRule(rule, {
          info: infoPlist(modes(['remote-notification'])),
          'pubspec.lock': lockOf(['firebase_messaging']),
        }),
        [
          isFinding(
            severity: Severity.warning,
            message: contains('firebase_messaging'),
          ),
        ],
      );
    });

    test('fails unknown modes', () {
      expect(
        runRule(rule, {
          info: infoPlist(modes(['background-audio'])),
        }),
        [isFinding(message: contains('not a background mode'))],
      );
    });

    test('processing needs BGTaskSchedulerPermittedIdentifiers', () {
      final findings = runRule(
        rule,
        {
          info: infoPlist(modes(['processing'])),
          'pubspec.lock': lockOf(['workmanager']),
        },
        options: {
          'allow': {'processing': 'Nightly sync of offline downloads.'},
        },
      );
      expect(findings, [
        isFinding(message: contains('BGTaskSchedulerPermittedIdentifiers')),
      ]);
    });

    test('extra evidence plugins count', () {
      expect(
        runRule(
          rule,
          {
            info: infoPlist(modes(['audio'])),
            'pubspec.lock': lockOf(['acme_player']),
          },
          options: {
            'extra_evidence': {
              'audio': ['acme_player'],
            },
          },
        ),
        [isFinding(severity: Severity.warning)],
      );
    });
  });

  group('export-options-build-number', () {
    const rule = ExportOptionsBuildNumberRule();

    String options(String body) => plist('''
  <key>method</key>
  <string>app-store-connect</string>
$body''');

    test('passes with manageAppVersionAndBuildNumber false', () {
      expect(
        runRule(rule, {
          'ios/ExportOptions.plist': options(
            '<key>manageAppVersionAndBuildNumber</key><false/>',
          ),
        }),
        isEmpty,
      );
    });

    test('fails when it is true', () {
      expect(
        runRule(rule, {
          'ios/ExportOptions.plist': options(
            '<key>manageAppVersionAndBuildNumber</key>\n  <true/>',
          ),
        }),
        [
          isFinding(
            severity: Severity.error,
            path: 'ios/ExportOptions.plist',
            line: 7,
          ),
        ],
      );
    });

    test('fails when it is absent, because the default is true', () {
      expect(
        runRule(rule, {
          'scripts/release/ExportOptions-AppStore.plist': options(''),
        }),
        [isFinding(message: contains('defaults to true'))],
      );
    });

    test('ignores non-App Store methods and build output', () {
      expect(
        runRule(rule, {
          'ios/ExportOptions.plist': plist(
            '<key>method</key><string>ad-hoc</string>',
          ),
          'build/ios/ipa/ExportOptions.plist': options(''),
        }),
        isEmpty,
      );
    });
  });

  group('bundle-localizations', () {
    const rule = BundleLocalizationsRule();

    String locs(List<String> values) =>
        '<key>CFBundleLocalizations</key>\n  <array>'
        '${values.map((v) => '<string>$v</string>').join()}</array>';

    Map<String, String> arb(List<String> locales) => {
      for (final l in locales) 'lib/l10n/app_$l.arb': '{"hello": "Hello"}',
    };

    test('passes when the lists agree, including regions', () {
      expect(
        runRule(rule, {
          info: infoPlist(locs(['en', 'pt-BR'])),
          ...arb(['en', 'pt_BR']),
        }),
        isEmpty,
      );
    });

    test('passes a single-language app without the key', () {
      expect(
        runRule(rule, {
          info: infoPlist(),
          ...arb(['en']),
        }),
        isEmpty,
      );
    });

    test('warns when the key is missing for a multilingual app', () {
      expect(
        runRule(rule, {
          info: infoPlist(),
          ...arb(['en', 'fr']),
        }),
        [
          isFinding(
            severity: Severity.warning,
            message: contains('ship en, fr'),
          ),
        ],
      );
    });

    test('warns about ARB locales the plist does not list, and vice versa', () {
      final findings = runRule(rule, {
        info: infoPlist(locs(['en', 'de'])),
        ...arb(['en', 'fr']),
      });
      expect(findings.map((f) => f.message), [
        contains('ships locale `fr`'),
        contains('lists `de`'),
      ]);
    });

    test('honours @@locale and l10n.yaml arb-dir', () {
      expect(
        runRule(rule, {
          info: infoPlist(locs(['en'])),
          'l10n.yaml': 'arb-dir: assets/translations\n',
          'assets/translations/strings.arb': '{"@@locale": "en"}',
          'assets/translations/extra.arb': '{"@@locale": "es"}',
        }),
        [isFinding(message: contains('`es`'))],
      );
    });

    test('a declared language backed by an .lproj directory is fine', () {
      expect(
        runRule(rule, {
          info: infoPlist(locs(['en', 'ja'])),
          'ios/Runner/ja.lproj/InfoPlist.strings': '',
          ...arb(['en']),
        }),
        isEmpty,
      );
    });
  });

  group('push-entitlement', () {
    const rule = PushEntitlementRule();
    const ent = 'ios/Runner/Runner.entitlements';

    test('passes when push is not used', () {
      expect(runRule(rule, {info: infoPlist()}), isEmpty);
    });

    test('passes when aps-environment is declared', () {
      expect(
        runRule(rule, {
          info: infoPlist(),
          ent: plist('<key>aps-environment</key><string>development</string>'),
          'pubspec.lock': lockOf(['firebase_messaging']),
        }),
        isEmpty,
      );
    });

    test('warns when a push SDK is linked without the entitlement', () {
      expect(
        runRule(rule, {
          info: infoPlist(),
          ent: plist(''),
          'pubspec.lock': lockOf(['firebase_messaging']),
        }),
        [isFinding(severity: Severity.warning, path: ent)],
      );
    });

    test('warns when remote-notification mode is declared without it', () {
      expect(
        runRule(rule, {
          info: infoPlist(modes(['remote-notification'])),
        }),
        [isFinding(message: contains('remote-notification'), path: info)],
      );
    });

    test('fails an invalid aps-environment value', () {
      expect(
        runRule(rule, {
          info: infoPlist(),
          ent: plist('<key>aps-environment</key><string>prod</string>'),
        }),
        [isFinding(severity: Severity.error)],
      );
    });
  });
}
