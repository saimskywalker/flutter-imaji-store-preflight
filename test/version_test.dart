import 'dart:io';

import 'package:imaji_store_preflight/imaji_store_preflight.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('packageVersion matches pubspec.yaml', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    expect(packageVersion, pubspec['version']);
    expect(packageName, pubspec['name']);
  });

  test('the changelog has an entry for the current version', () {
    expect(
      File('CHANGELOG.md').readAsStringSync(),
      contains('## $packageVersion'),
    );
  });

  test('every rule documents why, how to fix, and a public source', () {
    final ids = <String>{};
    for (final rule in builtInRules) {
      expect(ids.add(rule.id), isTrue, reason: 'duplicate id ${rule.id}');
      expect(rule.id, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')));
      expect(rule.title, isNotEmpty);
      expect(rule.why.length, greaterThan(80), reason: rule.id);
      expect(rule.fix, isNotEmpty, reason: rule.id);
      expect(rule.docs, isNotEmpty, reason: rule.id);
      for (final doc in rule.docs) {
        expect(doc, startsWith('https://'), reason: rule.id);
      }
    }
  });

  test('the README rule table lists every rule', () {
    final readme = File('README.md').readAsStringSync();
    for (final rule in builtInRules) {
      expect(readme, contains('`${rule.id}`'), reason: rule.id);
    }
  });
}
