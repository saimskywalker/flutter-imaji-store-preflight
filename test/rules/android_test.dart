import 'package:imaji_store_preflight/imaji_store_preflight.dart';
import 'package:imaji_store_preflight/src/rules/android.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

const manifestPath = 'android/app/src/main/AndroidManifest.xml';

String manifest([String queries = '']) =>
    '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="fixture">
        <activity android:name=".MainActivity" android:exported="true" />
    </application>
$queries
</manifest>
''';

const openDocumentQuery = '''
    <queries>
        <intent>
            <action android:name="android.intent.action.OPEN_DOCUMENT" />
            <category android:name="android.intent.category.OPENABLE" />
            <data android:mimeType="*/*" />
        </intent>
    </queries>''';

String gradle(String target, {String extra = ''}) =>
    '''
plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.fixture"
    defaultConfig {
        applicationId = "com.example.fixture"
        minSdk = 24
        targetSdk = $target
    }
$extra
}
''';

String settings(String agp) =>
    '''
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "$agp" apply false
}
''';

void main() {
  group('android-picker-queries', () {
    const rule = AndroidPickerQueriesRule();

    test('passes without a file picker', () {
      expect(runRule(rule, {manifestPath: manifest()}), isEmpty);
    });

    test('passes with the OPEN_DOCUMENT query', () {
      expect(
        runRule(rule, {
          manifestPath: manifest(openDocumentQuery),
          'pubspec.lock': lockOf(['file_picker']),
        }),
        isEmpty,
      );
    });

    test('fails when file_picker is linked without the query', () {
      expect(
        runRule(rule, {
          manifestPath: manifest(),
          'pubspec.lock': lockOf(['file_picker']),
        }),
        [
          isFinding(
            severity: Severity.error,
            path: manifestPath,
            line: 1,
            message: contains('OPEN_DOCUMENT'),
          ),
        ],
      );
    });

    test('a GET_CONTENT-only query is not enough', () {
      expect(
        runRule(rule, {
          manifestPath: manifest('''
    <queries>
        <intent>
            <action android:name="android.intent.action.GET_CONTENT" />
            <data android:mimeType="*/*" />
        </intent>
    </queries>'''),
          'pubspec.lock': lockOf(['file_picker']),
        }),
        [isFinding(severity: Severity.error, line: 5)],
      );
    });

    test('warns when the query has no mimeType', () {
      expect(
        runRule(rule, {
          manifestPath: manifest('''
    <queries>
        <intent>
            <action android:name="android.intent.action.OPEN_DOCUMENT" />
        </intent>
    </queries>'''),
          'pubspec.lock': lockOf(['file_picker']),
        }),
        [isFinding(severity: Severity.warning)],
      );
    });

    test('other picker plugins can be configured', () {
      expect(
        runRule(
          rule,
          {
            manifestPath: manifest(),
            'pubspec.lock': lockOf(['acme_files']),
          },
          options: {
            'plugins': ['acme_files'],
          },
        ),
        hasLength(1),
      );
    });
  });

  group('android-target-sdk', () {
    const rule = AndroidTargetSdkRule();
    const appGradle = 'android/app/build.gradle.kts';

    test('passes at the current requirement', () {
      expect(runRule(rule, {appGradle: gradle('36')}), isEmpty);
    });

    test('fails below the current requirement, pointing at the line', () {
      expect(runRule(rule, {appGradle: gradle('34')}), [
        isFinding(
          severity: Severity.error,
          path: appGradle,
          line: 11,
          message: allOf(contains('targetSdk is 34'), contains('at least 36')),
        ),
      ]);
    });

    test('warns ahead of an upcoming deadline', () {
      expect(
        runRule(
          rule,
          {appGradle: gradle('36')},
          options: {
            'deadlines': [
              {'api': 37, 'from': '2026-12-01'},
            ],
          },
        ),
        [isFinding(severity: Severity.warning, message: contains('61 days'))],
      );
    });

    test('a deadline row can be moved, e.g. for an extension', () {
      expect(
        runRule(
          rule,
          {appGradle: gradle('35')},
          options: {
            'deadlines': [
              {'api': 36, 'from': '2026-11-01'},
            ],
            'warn_days': 0,
          },
        ),
        isEmpty,
      );
    });

    test('reads Groovy scripts', () {
      expect(
        runRule(rule, {
          'android/app/build.gradle':
              'android {\n  defaultConfig {\n    targetSdkVersion 33\n  }\n}\n',
        }),
        [isFinding(line: 3, message: contains('targetSdk is 33'))],
      );
    });

    test('resolves flutter.targetSdkVersion through the Flutter SDK', () {
      final sdk = writeProject({
        'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt':
            'class FlutterExtension {\n  val targetSdkVersion: Int = 35\n}\n',
      });
      expect(
        runRule(
          rule,
          {appGradle: gradle('flutter.targetSdkVersion')},
          environment: {'FLUTTER_ROOT': sdk},
        ),
        [isFinding(message: contains('flutter.targetSdkVersion from'))],
      );
    });

    test('reports info when the value cannot be resolved', () {
      expect(runRule(rule, {appGradle: gradle('flutter.targetSdkVersion')}), [
        isFinding(severity: Severity.info, message: contains('target_sdk')),
      ]);
    });

    test('the target_sdk option overrides detection', () {
      expect(
        runRule(
          rule,
          {appGradle: gradle('flutter.targetSdkVersion')},
          options: {'target_sdk': 36},
        ),
        isEmpty,
      );
    });

    test('skips projects without Android', () {
      expect(runRule(rule, {}), isEmpty);
    });
  });

  group('android-16kb-page-size', () {
    const rule = Android16KbPageSizeRule();
    const appGradle = 'android/app/build.gradle.kts';
    const settingsGradle = 'android/settings.gradle.kts';

    test('passes with a current Android Gradle Plugin', () {
      expect(
        runRule(rule, {
          appGradle: gradle('36'),
          settingsGradle: settings('8.9.1'),
        }),
        isEmpty,
      );
    });

    test('warns about AGP before 8.5.1', () {
      expect(
        runRule(rule, {
          appGradle: gradle('36'),
          settingsGradle: settings('8.3.2'),
        }),
        [
          isFinding(
            severity: Severity.warning,
            path: settingsGradle,
            line: 3,
            message: contains('8.3.2'),
          ),
        ],
      );
    });

    test('legacy packaging is an accepted workaround', () {
      expect(
        runRule(rule, {
          appGradle: gradle(
            '36',
            extra: '    packaging { jniLibs { useLegacyPackaging = true } }',
          ),
          settingsGradle: settings('8.3.2'),
        }),
        isEmpty,
      );
    });

    test('reads the legacy buildscript classpath', () {
      expect(
        runRule(rule, {
          appGradle: gradle('35'),
          'android/build.gradle':
              "buildscript {\n  dependencies {\n    classpath 'com.android.tools.build:gradle:7.4.2'\n  }\n}\n",
        }),
        [isFinding(path: 'android/build.gradle', line: 3)],
      );
    });

    test('does not apply below API 35', () {
      expect(
        runRule(rule, {
          appGradle: gradle('34'),
          settingsGradle: settings('7.3.0'),
        }),
        isEmpty,
      );
    });

    test('warns about an old NDK when the module builds native code', () {
      expect(
        runRule(rule, {
          appGradle: gradle(
            '36',
            extra:
                '    ndkVersion = "27.0.12077973"\n'
                '    externalNativeBuild { cmake { path = file("CMakeLists.txt") } }',
          ),
          settingsGradle: settings('8.9.1'),
        }),
        [isFinding(message: contains('NDK 27'))],
      );
    });
  });
}
