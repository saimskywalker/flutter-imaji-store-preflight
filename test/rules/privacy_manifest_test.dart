import 'package:imaji_store_preflight/imaji_store_preflight.dart';
import 'package:imaji_store_preflight/src/rules/privacy_manifest.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

const manifestPath = 'ios/Runner/PrivacyInfo.xcprivacy';

String entry(
  String type, {
  bool linked = false,
  bool tracking = false,
  List<String> purposes = const ['AppFunctionality'],
}) =>
    '''
    <dict>
      <key>NSPrivacyCollectedDataType</key>
      <string>NSPrivacyCollectedDataType$type</string>
      <key>NSPrivacyCollectedDataTypeLinked</key>
      <${linked ? 'true' : 'false'}/>
      <key>NSPrivacyCollectedDataTypeTracking</key>
      <${tracking ? 'true' : 'false'}/>
      <key>NSPrivacyCollectedDataTypePurposes</key>
      <array>
${purposes.map((p) => '        <string>NSPrivacyCollectedDataTypePurpose$p</string>').join('\n')}
      </array>
    </dict>''';

String manifest({
  bool tracking = false,
  List<String> entries = const [],
  List<String> domains = const [],
  String extra = '',
}) => plist('''
  <key>NSPrivacyTracking</key>
  <${tracking ? 'true' : 'false'}/>
  <key>NSPrivacyTrackingDomains</key>
  <array>${domains.map((d) => '<string>$d</string>').join()}</array>
  <key>NSPrivacyCollectedDataTypes</key>
  <array>
${entries.join('\n')}
  </array>
$extra''');

void main() {
  group('privacy-manifest-present', () {
    const rule = PrivacyManifestPresentRule();

    test('passes when the manifest exists and is a bundle resource', () {
      expect(
        runRule(rule, {
          'ios/Runner/Info.plist': infoPlist(),
          manifestPath: manifest(),
          'ios/Runner.xcodeproj/project.pbxproj':
              '/* PrivacyInfo.xcprivacy in Resources */',
        }),
        isEmpty,
      );
    });

    test('passes for a project without iOS', () {
      expect(runRule(rule, {}), isEmpty);
    });

    test('warns when the manifest is missing', () {
      expect(runRule(rule, {'ios/Runner/Info.plist': infoPlist()}), [
        isFinding(severity: Severity.warning, message: contains('No privacy')),
      ]);
    });

    test('fails when the manifest is not in Copy Bundle Resources', () {
      expect(
        runRule(rule, {
          'ios/Runner/Info.plist': infoPlist(),
          manifestPath: manifest(),
          'ios/Runner.xcodeproj/project.pbxproj': '/* AppDelegate.swift */',
        }),
        [
          isFinding(
            severity: Severity.error,
            path: 'ios/Runner.xcodeproj/project.pbxproj',
            message: contains('never reaches the built app'),
          ),
        ],
      );
    });
  });

  group('privacy-manifest-values', () {
    const rule = PrivacyManifestValuesRule();

    test('passes for Apple values', () {
      expect(
        runRule(rule, {
          manifestPath: manifest(
            entries: [
              entry('CrashData', purposes: ['Analytics', 'AppFunctionality']),
              entry('PhotosorVideos'),
            ],
            extra: '''
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array><string>CA92.1</string></array>
    </dict>
  </array>''',
          ),
        }),
        isEmpty,
      );
    });

    test('flags misspelt types and purposes, with a suggestion', () {
      final findings = runRule(rule, {
        manifestPath: manifest(
          entries: [
            entry('PhotosOrVideos'),
            entry('CrashData', purposes: ['Analytic']),
          ],
        ),
      });
      expect(findings, [
        isFinding(
          severity: Severity.error,
          message: allOf(
            contains('PhotosOrVideos` is not a data type'),
            contains('did you mean `NSPrivacyCollectedDataTypePhotosorVideos`'),
          ),
          path: manifestPath,
          line: isNotNull,
        ),
        isFinding(message: contains('PurposeAnalytic` is not a purpose')),
      ]);
    });

    test('flags duplicates, missing booleans and missing purposes', () {
      final findings = runRule(rule, {
        manifestPath: manifest(
          entries: [
            entry('CrashData'),
            entry('CrashData'),
            '''
    <dict>
      <key>NSPrivacyCollectedDataType</key>
      <string>NSPrivacyCollectedDataTypeUserID</string>
    </dict>''',
          ],
        ),
      });
      expect(findings.map((f) => f.message), [
        contains('declared more than once'),
        contains('needs `NSPrivacyCollectedDataTypeLinked`'),
        contains('needs `NSPrivacyCollectedDataTypeTracking`'),
        contains('declares no `NSPrivacyCollectedDataTypePurposes`'),
      ]);
    });

    test('flags unknown API categories and reasons', () {
      final findings = runRule(rule, {
        manifestPath: manifest(
          extra: '''
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryDiskSpace</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array><string>CA92.1</string></array>
    </dict>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryClipboard</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array><string>1234.1</string></array>
    </dict>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
    </dict>
  </array>''',
        ),
      });
      expect(findings.map((f) => f.message), [
        contains('`CA92.1` is not an approved reason'),
        contains('Clipboard` is not a required-reason API category'),
        contains('lists no `NSPrivacyAccessedAPITypeReasons`'),
      ]);
    });

    test('warns about unknown top-level keys', () {
      expect(
        runRule(rule, {
          manifestPath: manifest(
            extra: '<key>NSPrivacyTrackingDomain</key><array/>',
          ),
        }),
        [isFinding(severity: Severity.warning, message: contains('Unknown'))],
      );
    });

    test('extra values from options are accepted', () {
      expect(
        runRule(
          rule,
          {
            manifestPath: manifest(
              entries: [
                entry('BrainWaves', purposes: ['Telepathy']),
              ],
            ),
          },
          options: {
            'extra_data_types': ['BrainWaves'],
            'extra_purposes': ['NSPrivacyCollectedDataTypePurposeTelepathy'],
          },
        ),
        isEmpty,
      );
    });

    test('rejects wrongly typed top-level values', () {
      final findings = runRule(rule, {
        manifestPath: plist('''
  <key>NSPrivacyTracking</key>
  <string>NO</string>
  <key>NSPrivacyCollectedDataTypes</key>
  <dict/>'''),
      });
      expect(findings.map((f) => f.message), [
        contains('must be <true/> or <false/>'),
        contains('must be an array of dictionaries'),
      ]);
    });
  });

  group('privacy-manifest-tracking', () {
    const rule = PrivacyManifestTrackingRule();

    test('passes when nothing tracks', () {
      expect(
        runRule(rule, {
          manifestPath: manifest(entries: [entry('CrashData')]),
        }),
        isEmpty,
      );
    });

    test('passes when tracking is declared with domains', () {
      expect(
        runRule(rule, {
          manifestPath: manifest(
            tracking: true,
            domains: ['ads.example.com'],
            entries: [entry('AdvertisingData', tracking: true)],
          ),
        }),
        isEmpty,
      );
    });

    test(
      'fails on tracking entries and domains under NSPrivacyTracking false',
      () {
        final findings = runRule(rule, {
          manifestPath: manifest(
            domains: ['ads.example.com'],
            entries: [entry('DeviceID', tracking: true)],
          ),
        });
        expect(findings, [
          isFinding(
            severity: Severity.error,
            message: contains('DeviceID` is marked as used for tracking'),
          ),
          isFinding(
            severity: Severity.error,
            message: contains('NSPrivacyTrackingDomains` lists 1 domain'),
          ),
        ]);
      },
    );

    test('warns when tracking is declared without domains', () {
      expect(runRule(rule, {manifestPath: manifest(tracking: true)}), [
        isFinding(severity: Severity.warning),
      ]);
    });
  });

  group('privacy-manifest-sdk-data', () {
    const rule = PrivacyManifestSdkDataRule();

    test('passes when no collecting SDK is linked', () {
      expect(
        runRule(rule, {
          manifestPath: manifest(),
          'pubspec.lock': lockOf(['http']),
        }),
        isEmpty,
      );
    });

    test('passes when every implied type is declared', () {
      expect(
        runRule(rule, {
          manifestPath: manifest(
            entries: [entry('CrashData'), entry('PerformanceData')],
          ),
          'pubspec.lock': lockOf([
            'firebase_crashlytics',
            'firebase_performance',
          ]),
        }),
        isEmpty,
      );
    });

    test('fails when collected data is empty but an SDK collects', () {
      expect(
        runRule(rule, {
          manifestPath: manifest(),
          'pubspec.lock': lockOf(['firebase_analytics']),
        }),
        [
          isFinding(
            severity: Severity.error,
            message: allOf(
              contains('declares no collected data'),
              contains('firebase_analytics (ProductInteraction, DeviceID)'),
            ),
          ),
        ],
      );
    });

    test('also reads transitive dependencies but not dev ones', () {
      expect(
        runRule(rule, {
          manifestPath: manifest(),
          'pubspec.lock': lock({'firebase_crashlytics': 'transitive'}),
        }),
        hasLength(1),
      );
      expect(
        runRule(rule, {
          manifestPath: manifest(),
          'pubspec.lock': lock({'sentry_flutter': 'direct dev'}),
        }),
        isEmpty,
      );
    });

    test('falls back to pubspec.yaml dependencies without a lock file', () {
      expect(
        runRule(rule, {
          manifestPath: manifest(),
          'pubspec.yaml':
              'name: fixture_app\ndependencies:\n  in_app_purchase: ^3.0.0\n',
        }),
        [isFinding(message: contains('in_app_purchase (PurchaseHistory)'))],
      );
    });

    test('warns about individual missing types', () {
      expect(
        runRule(rule, {
          manifestPath: manifest(entries: [entry('ProductInteraction')]),
          'pubspec.lock': lockOf(['firebase_analytics']),
        }),
        [
          isFinding(
            severity: Severity.warning,
            message: contains('NSPrivacyCollectedDataTypeDeviceID'),
          ),
        ],
      );
    });

    test('the table can be extended and overridden', () {
      final files = {
        manifestPath: manifest(entries: [entry('CrashData')]),
        'pubspec.lock': lockOf(['firebase_analytics', 'acme_metrics']),
      };
      expect(
        runRule(
          rule,
          files,
          options: {
            'sdk_data_types': {
              'firebase_analytics': <String>[],
              'acme_metrics': ['CrashData'],
            },
          },
        ),
        isEmpty,
      );
    });
  });

  group('tracking-usage-description', () {
    const rule = TrackingUsageDescriptionRule();
    const att =
        '<key>NSUserTrackingUsageDescription</key>'
        '<string>Shows ads that match your interests, for example nearby '
        'concerts.</string>';

    test('passes when neither side tracks', () {
      expect(
        runRule(rule, {
          'ios/Runner/Info.plist': infoPlist(),
          manifestPath: manifest(),
        }),
        isEmpty,
      );
    });

    test('passes when both sides track', () {
      expect(
        runRule(rule, {
          'ios/Runner/Info.plist': infoPlist(att),
          manifestPath: manifest(tracking: true),
        }),
        isEmpty,
      );
    });

    test('fails when the purpose string exists but tracking is false', () {
      expect(
        runRule(rule, {
          'ios/Runner/Info.plist': infoPlist(att),
          manifestPath: manifest(),
        }),
        [
          isFinding(
            severity: Severity.error,
            path: 'ios/Runner/Info.plist',
            line: isNotNull,
            message: contains('declares `NSPrivacyTracking` false'),
          ),
        ],
      );
    });

    test('fails when tracking is declared without the purpose string', () {
      expect(
        runRule(rule, {
          'ios/Runner/Info.plist': infoPlist(),
          manifestPath: manifest(tracking: true),
        }),
        [isFinding(severity: Severity.error, path: manifestPath)],
      );
    });

    test('warns when the ATT plugin is linked without the purpose string', () {
      expect(
        runRule(rule, {
          'ios/Runner/Info.plist': infoPlist(),
          manifestPath: manifest(),
          'pubspec.lock': lockOf(['app_tracking_transparency']),
        }),
        [
          isFinding(
            severity: Severity.warning,
            message: contains('terminates'),
          ),
        ],
      );
    });
  });
}
