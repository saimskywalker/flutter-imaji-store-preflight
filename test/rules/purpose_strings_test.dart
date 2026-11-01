import 'package:imaji_store_preflight/imaji_store_preflight.dart';
import 'package:imaji_store_preflight/src/data/linked_api_references.dart';
import 'package:imaji_store_preflight/src/rules/purpose_strings.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

const info = 'ios/Runner/Info.plist';
const whenInUse = 'NSLocationWhenInUseUsageDescription';
const always = 'NSLocationAlwaysAndWhenInUseUsageDescription';

/// An honest string for a key a bundled SDK only references.
const notUsedLocation =
    'This app does not use your location. iOS requires this text because a '
    'third-party SDK included in the app references location APIs; the app '
    'never requests location access.';

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

  group('purpose-string-missing, linked-only references', () {
    const rule = PurposeStringMissingRule();
    const linkedCalls = {
      'linked_by_plugin': {
        'acme_calls': ['NSMotionUsageDescription'],
      },
    };

    test('reports a referenced key as referenced, not requested', () {
      expect(
        runRule(rule, {
          info: infoPlist(),
          'pubspec.lock': lock({'acme_calls': 'transitive'}),
        }, options: linkedCalls),
        [
          isFinding(
            severity: Severity.error,
            message: allOf(
              contains('`NSMotionUsageDescription` is missing'),
              contains('acme_calls references'),
              contains('referenced, not requested'),
              contains('ITMS-90683'),
            ),
          ),
        ],
      );
    });

    test('passes when the referenced key is present', () {
      expect(
        runRule(rule, {
          info: infoPlist(key('NSMotionUsageDescription', 'x')),
          'pubspec.lock': lockOf(['acme_calls']),
        }, options: linkedCalls),
        isEmpty,
      );
    });

    test('ignores references from packages that are not linked', () {
      expect(
        runRule(rule, {
          info: infoPlist(),
          'pubspec.lock': lock({'acme_calls': 'direct dev'}),
        }, options: linkedCalls),
        isEmpty,
      );
    });

    test('a location reference requires both location keys', () {
      final options = {
        'linked_by_plugin': {
          'acme_calls': [whenInUse],
        },
      };
      final files = {
        'pubspec.lock': lockOf(['acme_calls']),
      };
      expect(runRule(rule, {...files, info: infoPlist()}, options: options), [
        isFinding(message: contains('`$whenInUse` is missing')),
        isFinding(
          message: allOf(
            contains('`$always` is missing'),
            contains('Always authorization API'),
          ),
        ),
      ]);
      expect(
        runRule(rule, {
          ...files,
          info: infoPlist(key(whenInUse, 'x')),
        }, options: options),
        [isFinding(message: contains('`$always` is missing'))],
      );
      expect(
        runRule(rule, {
          ...files,
          info: infoPlist(key(always, 'x')),
        }, options: options),
        [isFinding(message: contains('`$whenInUse` is missing'))],
      );
      expect(
        runRule(rule, {
          ...files,
          info: infoPlist(key(whenInUse, 'x') + key(always, 'x')),
        }, options: options),
        isEmpty,
      );
    });

    test('a key a linked plugin requests keeps the requesting message', () {
      expect(
        runRule(
          rule,
          {
            info: infoPlist(key('NSCameraUsageDescription', 'x')),
            'pubspec.lock': lockOf(['camera', 'acme_calls']),
          },
          options: {
            'linked_by_plugin': {
              'acme_calls': ['NSMicrophoneUsageDescription'],
            },
          },
        ),
        [
          isFinding(
            message: allOf(
              contains('`NSMicrophoneUsageDescription` is missing'),
              contains('camera needs it'),
            ),
          ),
        ],
      );
    });

    test('validates linked_by_plugin', () {
      expect(
        rule.validateOptions({
          'linked_by_plugin': {'acme_calls': 'NSMotionUsageDescription'},
        }),
        contains('linked_by_plugin'),
      );
      expect(rule.validateOptions(linkedCalls), isNull);
    });

    test('built-in rows name the versions their evidence covers', () {
      const withRow = PurposeStringMissingRule(
        linkedReferences: {
          'acme_calls': LinkedApiReference(
            keys: ['NSMotionUsageDescription'],
            versions: '2.x',
            evidence: 'synthetic row for this test',
          ),
        },
      );
      expect(
        runRule(withRow, {
          info: infoPlist(),
          'pubspec.lock': lockOf(['acme_calls']),
        }),
        [isFinding(message: contains('acme_calls 2.x references'))],
      );
    });

    test('every built-in row records its versions and evidence', () {
      for (final MapEntry(:key, :value) in linkedApiReferences.entries) {
        expect(value.keys, isNotEmpty, reason: key);
        expect(value.versions.trim(), isNotEmpty, reason: key);
        expect(value.evidence.trim(), isNotEmpty, reason: key);
      }
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

    group('keys the app does not use', () {
      test('passes an honest "not used" string without an example', () {
        expect(check(whenInUse, notUsedLocation), isEmpty);
        expect(
          check(
            'NSMotionUsageDescription',
            'The app never uses motion data; the video calling SDK it bundles '
                'references the motion APIs, so iOS requires this key.',
          ),
          isEmpty,
        );
      });

      test('passes a hand-checked string listed under linked_only', () {
        const text =
            'Aplikasi ini tidak memakai sensor gerak; pustaka panggilan '
            'video di dalamnya merujuk API tersebut.';
        expect(check('NSMotionUsageDescription', text), [
          isFinding(severity: Severity.warning),
        ]);
        expect(
          check(
            'NSMotionUsageDescription',
            text,
            options: {
              'linked_only': {
                'NSMotionUsageDescription': 'Referenced by the calling SDK.',
              },
            },
          ),
          isEmpty,
        );
      });

      test('validates linked_only and extra_unused_markers', () {
        expect(
          rule.validateOptions({
            'linked_only': {whenInUse: ''},
          }),
          contains('linked_only'),
        );
        expect(
          rule.validateOptions({'extra_unused_markers': 'never'}),
          contains('extra_unused_markers'),
        );
      });

      test('extra_unused_markers extends the wording it recognises', () {
        const text =
            'No feature of the app reads motion data; the bundled calling '
            'SDK references the motion APIs.';
        expect(check('NSMotionUsageDescription', text), [
          isFinding(message: contains('gives no example')),
        ]);
        expect(
          check(
            'NSMotionUsageDescription',
            text,
            options: {
              'extra_unused_markers': ['No feature of the app'],
            },
          ),
          isEmpty,
        );
      });

      for (final options in [
        <String, Object?>{},
        {
          'linked_only': {whenInUse: 'Referenced by the calling SDK.'},
        },
      ]) {
        test('still fails "Not used." ($options)', () {
          expect(check(whenInUse, 'Not used.', options: options), [
            isFinding(
              severity: Severity.error,
              message: contains('why the key is present'),
            ),
          ]);
        });
      }

      test('warns when a "not used" string gives no reason', () {
        expect(
          check(
            'NSMotionUsageDescription',
            'This app does not use motion data at all, not even briefly.',
          ),
          [
            isFinding(
              severity: Severity.warning,
              message: contains('not why the key is present'),
            ),
          ],
        );
      });

      test('fails a "not used" string next to a plugin that requests it', () {
        expect(
          runRule(rule, {
            info: infoPlist(key(whenInUse, notUsedLocation)),
            'pubspec.lock': lockOf(['geolocator']),
          }),
          [
            isFinding(
              severity: Severity.error,
              message: allOf(
                contains('says the app does not use the resource'),
                contains('geolocator is linked and requests'),
              ),
              line: isNotNull,
            ),
          ],
        );
        expect(
          runRule(
            rule,
            {
              info: infoPlist(
                key(
                  'NSFaceIDUsageDescription',
                  'Aplikasi ini tidak memakai Face ID; pustaka penyimpanan '
                      'aman di dalamnya merujuk API tersebut.',
                ),
              ),
              'pubspec.lock': lockOf(['local_auth']),
            },
            options: {
              'linked_only': {
                'NSFaceIDUsageDescription': 'Keychain plugin links it.',
              },
            },
          ),
          [
            isFinding(
              severity: Severity.error,
              message: contains('local_auth'),
            ),
          ],
        );
      });

      test('only warns when the requesting plugin is transitive', () {
        expect(
          runRule(rule, {
            info: infoPlist(key(whenInUse, notUsedLocation)),
            'pubspec.lock': lock({'geolocator': 'transitive'}),
          }),
          [
            isFinding(
              severity: Severity.warning,
              message: contains('pulled in by another package'),
            ),
          ],
        );
      });

      test('a limit on a real use is not a "not used" string', () {
        expect(
          runRule(rule, {
            info: infoPlist(
              key(
                whenInUse,
                'Your location is not used for advertising; the map shows '
                'stores near you, for example the closest pharmacy.',
              ),
            ),
            'pubspec.lock': lockOf(['geolocator']),
          }),
          isEmpty,
        );
        expect(
          runRule(rule, {
            info: infoPlist(
              key(
                whenInUse,
                'Your location is not used for ads. It is required to show '
                'the stores near you on the map.',
              ),
            ),
            'pubspec.lock': lockOf(['geolocator']),
          }),
          [isFinding(message: contains('gives no example'))],
        );
      });
    });

    test('derives vocabulary for keys it has no table entry for', () {
      expect(
        PurposeStringQualityRule.vocabularyFor('NSHomeKitUsageDescription'),
        containsAll(['home', 'kit']),
      );
    });
  });
}
