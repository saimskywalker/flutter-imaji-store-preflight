import 'dart:convert';
import 'dart:typed_data';

import 'package:imaji_store_preflight/src/plist.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('parsePlistString', () {
    test('reads every value type and remembers key lines', () {
      final root =
          parsePlistString(
                plist('''
  <key>Name</key>
  <string>Fixture &amp; Co</string>
  <key>Flag</key>
  <true/>
  <key>Off</key>
  <false/>
  <key>Count</key>
  <integer>42</integer>
  <key>Ratio</key>
  <real>0.5</real>
  <key>List</key>
  <array>
    <string>a</string>
    <dict><key>k</key><string>v</string></dict>
  </array>
  <key>When</key>
  <date>2026-01-01T00:00:00Z</date>'''),
              )
              as PlistDict;

      expect(root.string('Name'), 'Fixture & Co');
      expect(root.boolean('Flag'), isTrue);
      expect(root.boolean('Off'), isFalse);
      expect((root['Count'] as PlistNumber).value, 42);
      expect((root['Ratio'] as PlistNumber).value, 0.5);
      final list = root.array('List')!;
      expect(list.strings.single.value, 'a');
      expect((list.items[1] as PlistDict).string('k'), 'v');
      expect(root['When'], isA<PlistOpaque>());
      expect(root.lineOf('Name'), 5);
      expect(root.lineOf('Flag'), 7);
    });

    test('ignores comments, even ones that mention keys', () {
      final root =
          parsePlistString(
                plist('''
  <!-- <key>Hidden</key><string>x</string> -->
  <key>Shown</key>
  <string>y</string>'''),
              )
              as PlistDict;
      expect(root.entries.keys, ['Shown']);
    });

    test('rejects a key without a value', () {
      expect(
        () => parsePlistString(plist('<key>Lonely</key>')),
        throwsA(
          isA<PlistFormatException>().having(
            (e) => e.message,
            'message',
            contains('has no value'),
          ),
        ),
      );
    });

    test('rejects malformed XML with a line number', () {
      expect(
        () => parsePlistString(plist('<key>A</key>\n<string>oops</strin>')),
        throwsA(
          isA<PlistFormatException>().having((e) => e.line, 'line', isNotNull),
        ),
      );
    });

    test('rejects a non-plist root element', () {
      expect(
        () => parsePlistString('<root/>'),
        throwsA(isA<PlistFormatException>()),
      );
    });

    test('explains OpenStep property lists', () {
      expect(
        () => parsePlistString('{ Key = Value; }'),
        throwsA(
          isA<PlistFormatException>().having(
            (e) => e.message,
            'message',
            contains('plutil'),
          ),
        ),
      );
    });
  });

  group('parsePlistBytes', () {
    test('refuses binary property lists with a conversion hint', () {
      final bytes = Uint8List.fromList([
        ...ascii.encode('bplist00'),
        0xD1,
        0x01,
        0x02,
      ]);
      expect(
        () => parsePlistBytes(bytes),
        throwsA(
          isA<PlistFormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('binary'), contains('plutil -convert xml1')),
          ),
        ),
      );
    });

    test('refuses invalid UTF-8', () {
      expect(
        () => parsePlistBytes(Uint8List.fromList([0x3C, 0xFF, 0xFE])),
        throwsA(isA<PlistFormatException>()),
      );
    });
  });
}
