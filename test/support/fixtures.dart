import 'dart:io';

import 'package:imaji_store_preflight/imaji_store_preflight.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A fixed date so deadline rules are deterministic.
final fixedToday = DateTime.utc(2026, 10, 1);

/// Writes a synthetic project to a temporary directory that is deleted after
/// the test, and returns its path.
String writeProject(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('isp_fixture_');
  addTearDown(() => dir.deleteSync(recursive: true));
  files.putIfAbsent('pubspec.yaml', () => 'name: fixture_app\n');
  for (final MapEntry(key: path, value: content) in files.entries) {
    final file = File(p.joinAll([dir.path, ...path.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }
  return dir.path;
}

/// Wraps [body] (the inside of the root `<dict>`) in an XML property list.
String plist(String body) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
$body
</dict>
</plist>
''';

/// A `pubspec.lock` listing [packages] (name to dependency kind, e.g.
/// `direct main`, `direct dev`, `transitive`).
String lock(Map<String, String> packages) {
  final out = StringBuffer('packages:\n');
  for (final MapEntry(key: name, value: kind) in packages.entries) {
    out
      ..writeln('  $name:')
      ..writeln('    dependency: "$kind"')
      ..writeln('    description:')
      ..writeln('      name: $name')
      ..writeln('      url: "https://pub.dev"')
      ..writeln('    source: hosted')
      ..writeln('    version: "1.0.0"');
  }
  out.writeln('sdks:\n  dart: ">=3.8.0 <4.0.0"');
  return out.toString();
}

/// A lock file with each of [names] as a direct main dependency.
String lockOf(List<String> names) =>
    lock({for (final n in names) n: 'direct main'});

/// A minimal valid Info.plist plus [body].
String infoPlist([String body = '']) => plist('''
  <key>CFBundleDisplayName</key>
  <string>Fixture</string>
  <key>CFBundleIdentifier</key>
  <string>com.example.fixture</string>
$body''');

/// Runs a single [rule] against a project built from [files].
List<Finding> runRule(
  Rule rule,
  Map<String, String> files, {
  Map<String, Object?> options = const {},
  DateTime? today,
  Map<String, String> environment = const {},
}) {
  final root = writeProject(files);
  final report = runPreflight(
    root,
    rules: [rule],
    today: today ?? fixedToday,
    environment: environment,
    config: PreflightConfig(rules: {rule.id: RuleConfig(options: options)}),
  );
  return report.findings;
}

/// Matches a finding with the given properties.
Matcher isFinding({
  Severity? severity,
  Object? message,
  String? path,
  Object? line,
}) {
  var m = isA<Finding>();
  if (severity != null) m = m.having((f) => f.severity, 'severity', severity);
  if (message != null) m = m.having((f) => f.message, 'message', message);
  if (path != null) m = m.having((f) => f.path, 'path', path);
  if (line != null) m = m.having((f) => f.line, 'line', line);
  return m;
}
