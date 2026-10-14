import 'package:imaji_store_preflight/imaji_store_preflight.dart';
import 'package:imaji_store_preflight/src/rules/purpose_strings.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

const info = 'ios/Runner/Info.plist';

String key(String name, String value) =>
    '<key>$name</key>\n  <string>$value</string>';

void main() {
  group('purpose-string-missing', () {
    const rule = PurposeStringMissingRule();

    test('passes when every needed key is present', () {
      expect(
        runRule(rule, {
          info: infoPlist(
            key('NSCameraUsageDescription', 'x') +
                key('NSMicrophoneUsageDescription', 'x'),
          ),
          'pubspec.lock': lockOf(['camera']),
        }),
        isEmpty,
      );
    });

    test('fails for each missing key, naming the plugins', () {
      final findings = runRule(rule, {
        info: infoPlist(key('NSCameraUsageDescription', 'x')),
        'pubspec.lock': lockOf(['camera', 'record']),
      });
      expect(findings, [
        isFinding(
          severity: Severity.error,
          message: allOf(
            contains('NSMicrophoneUsageDescription'),
            contains('camera, record need it'),
          ),
        ),
      ]);
    });

    test('requires WhenInUse next to Always', () {
      expect(
        runRule(rule, {
          info: infoPlist(
            key('NSLocationAlwaysAndWhenInUseUsageDescription', 'x'),
          ),
        }),
        [isFinding(message: contains('NSLocationWhenInUseUsageDescription'))],
      );
    });

    test('the plugin table can be extended', () {
      expect(
        runRule(
          rule,
          {
            info: infoPlist(),
            'pubspec.lock': lockOf(['acme_scanner']),
          },
          options: {
            'required_by_plugin': {
              'acme_scanner': ['NSCameraUsageDescription'],
            },
          },
        ),
        hasLength(1),
      );
    });
  });

  group('purpose-string-quality', () {
    const rule = PurposeStringQualityRule();

    List<Finding> check(
      String name,
      String value, {
      Map<String, Object?> options = const {},
    }) => runRule(rule, {info: infoPlist(key(name, value))}, options: options);

    test('passes a string that names a feature and gives an example', () {
      expect(
        check(
          'NSMicrophoneUsageDescription',
          'Your microphone records the voice notes you send in chat, for '
              'example a reply to a friend’s photo.',
        ),
        isEmpty,
      );
      expect(
        check(
          'NSCameraUsageDescription',
          r'$(PRODUCT_NAME) uses the camera to scan ticket barcodes at the '
              'venue entrance, such as the QR code on your booking email.',
        ),
        isEmpty,
      );
    });

    for (final restatement in [
      'Fixture needs microphone access to record video.',
      'This app requires access to your microphone.',
      'Allow microphone access',
      r'$(PRODUCT_NAME) needs access to the microphone so you can record audio.',
      'We need your permission to use the mic.',
    ]) {
      test('fails a restatement: "$restatement"', () {
        expect(check('NSMicrophoneUsageDescription', restatement), [
          isFinding(
            severity: Severity.error,
            message: contains('only restates the permission'),
            line: isNotNull,
          ),
        ]);
      });
    }

    test('fails a camera restatement that only adds the app name', () {
      expect(
        check(
          'NSCameraUsageDescription',
          'Glimmerstream needs camera access to take photos.',
          options: {
            'app_names': ['Glimmerstream'],
          },
        ),
        [isFinding(message: contains('restates'))],
      );
    });

    test('fails empty and placeholder strings', () {
      expect(check('NSCameraUsageDescription', '  '), [
        isFinding(message: contains('is empty')),
      ]);
      expect(check('NSCameraUsageDescription', r'$(PRODUCT_NAME)'), [
        isFinding(message: contains('is empty')),
      ]);
      expect(check('NSCameraUsageDescription', 'TODO write this'), [
        isFinding(message: contains('placeholder')),
      ]);
    });

    test('warns when a real description has no example', () {
      expect(
        check(
          'NSPhotoLibraryUsageDescription',
          'Choose a cover image for each playlist you create and share.',
        ),
        [
          isFinding(
            severity: Severity.warning,
            message: contains('gives no example'),
          ),
        ],
      );
    });

    test('warns when a description is too short', () {
      expect(
        check(
          'NSPhotoLibraryUsageDescription',
          'Playlist covers, for example yours.',
        ),
        [isFinding(severity: Severity.warning, message: contains('too short'))],
      );
    });

    test('options relax the heuristics', () {
      expect(
        check(
          'NSPhotoLibraryUsageDescription',
          'Choose playlist covers.',
          options: {'min_words': 2, 'require_example': false},
        ),
        isEmpty,
      );
      expect(
        check(
          'NSPhotoLibraryUsageDescription',
          'Choose a cover image for each playlist, say a holiday snapshot.',
          options: {
            'extra_example_markers': ['say'],
          },
        ),
        isEmpty,
      );
    });

    test('rejects non-string values', () {
      expect(
        runRule(rule, {
          info: infoPlist('<key>NSCameraUsageDescription</key><true/>'),
        }),
        [isFinding(message: contains('must be a string'))],
      );
    });

    test('derives vocabulary for keys it has no table entry for', () {
      expect(
        PurposeStringQualityRule.vocabularyFor('NSHomeKitUsageDescription'),
        containsAll(['home', 'kit']),
      );
    });
  });
}
