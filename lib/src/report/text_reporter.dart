import '../engine.dart';
import '../finding.dart';
import '../rule.dart';
import 'paths.dart';

/// Renders a report for people: findings grouped by rule, each group followed
/// by why the rule exists and how to fix it.
String renderText(
  PreflightReport report, {
  String pathPrefix = '',
  bool color = false,
  bool explain = true,
}) {
  String paint(String text, String code) =>
      color ? '\x1B[${code}m$text\x1B[0m' : text;
  String sev(Severity s) => switch (s) {
    Severity.error => paint('error', '31;1'),
    Severity.warning => paint('warning', '33;1'),
    Severity.info => paint('info', '36'),
  };
  String where(Finding f) {
    if (f.path == null) return '<project>';
    final path = displayPath(pathPrefix, f.path!);
    return f.line == null ? path : '$path:${f.line}';
  }

  final out = StringBuffer();
  final byRule = <String, List<Finding>>{};
  for (final f in report.findings) {
    byRule.putIfAbsent(f.ruleId, () => []).add(f);
  }
  for (final MapEntry(key: id, value: findings) in byRule.entries) {
    final rule = report.ruleById(id);
    out.writeln(paint('$id — ${rule?.title ?? ''}', '1'));
    for (final f in findings) {
      out.writeln('  ${sev(f.severity)}  ${paint(where(f), '4')}');
      out.writeln(_indent(f.message, '    '));
    }
    if (explain && rule != null) {
      out.writeln(_indent('why: ${rule.why}', '  '));
      out.writeln(_indent('fix: ${rule.fix}', '  '));
      if (rule.docs.isNotEmpty) {
        out.writeln('  docs: ${rule.docs.first}');
      }
    }
    out.writeln();
  }

  if (report.suppressed.isNotEmpty) {
    out.writeln('Suppressed by `ignore`:');
    for (final s in report.suppressed) {
      out.writeln(
        '  ${s.finding.ruleId}  ${where(s.finding)}  — ${s.entry.reason}',
      );
    }
    out.writeln();
  }
  if (report.disabled.isNotEmpty) {
    out.writeln('Disabled rules:');
    for (final d in report.disabled) {
      out.writeln('  ${d.rule.id}  — ${d.reason}');
    }
    out.writeln();
  }
  if (report.unusedIgnores.isNotEmpty) {
    out.writeln(
      paint('Unused `ignore` entries (nothing matched; delete them?):', '33'),
    );
    for (final e in report.unusedIgnores) {
      out.writeln('  ${e.describe()}');
    }
    out.writeln();
  }

  final e = report.count(Severity.error);
  final w = report.count(Severity.warning);
  final i = report.count(Severity.info);
  final parts = [
    _plural(e, 'error'),
    _plural(w, 'warning'),
    '$i info',
    if (report.suppressed.isNotEmpty) '${report.suppressed.length} suppressed',
    if (report.disabled.isNotEmpty)
      '${_plural(report.disabled.length, 'rule')} disabled',
  ];
  final summary = '${report.rules.length} rules checked: ${parts.join(', ')}.';
  if (report.findings.isEmpty) {
    out.writeln(paint('✓ $summary', '32'));
  } else if (report.failed) {
    out.writeln(
      paint(
        '✗ $summary Failing: findings at or above `${report.failOn!.name}`.',
        '31;1',
      ),
    );
  } else {
    out.writeln(summary);
  }
  return out.toString();
}

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

/// Prefixes every line of [text] with [prefix], word-wrapping paragraphs to
/// [width] columns. Lines that start with spaces (code) are left alone.
String _indent(String text, String prefix, {int width = 80}) {
  final out = <String>[];
  for (final line in text.split('\n')) {
    if (line.startsWith(' ') || prefix.length + line.length <= width) {
      out.add('$prefix$line');
      continue;
    }
    var current = StringBuffer(prefix);
    var empty = true;
    for (final word in line.split(' ')) {
      if (!empty && current.length + 1 + word.length > width) {
        out.add(current.toString());
        current = StringBuffer(prefix);
        empty = true;
      }
      if (!empty) current.write(' ');
      current.write(word);
      empty = false;
    }
    out.add(current.toString());
  }
  return out.join('\n');
}

/// Renders `--list-rules` output.
String renderRuleList(List<Rule> rules) {
  final out = StringBuffer();
  for (final platform in RulePlatform.values) {
    final group = rules.where((r) => r.platform == platform).toList();
    if (group.isEmpty) continue;
    out.writeln(switch (platform) {
      RulePlatform.ios => 'iOS / App Store',
      RulePlatform.android => 'Android / Google Play',
      RulePlatform.general => 'General',
    });
    for (final r in group) {
      out.writeln(
        '  ${r.id.padRight(30)} ${r.defaultSeverity.name.padRight(8)}'
        ' ${r.title}',
      );
    }
    out.writeln();
  }
  out.write(
    'Run `--explain <rule-id>` for why a rule exists and how to fix '
    'its findings.',
  );
  return out.toString();
}

/// Renders `--explain <id>` output.
String renderExplain(Rule rule) {
  final out = StringBuffer()
    ..writeln(
      '${rule.id} (${rule.defaultSeverity.name}, '
      '${rule.platform.name})',
    )
    ..writeln(rule.title)
    ..writeln()
    ..writeln('Why it matters:')
    ..writeln(_indent(rule.why, '  '))
    ..writeln()
    ..writeln('How to fix:')
    ..writeln(_indent(rule.fix, '  '));
  if (rule.optionKeys.isNotEmpty) {
    out
      ..writeln()
      ..writeln(
        'Options (under `rules.${rule.id}:`): '
        '${(rule.optionKeys.toList()..sort()).join(', ')}',
      );
  }
  if (rule.docs.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Documentation:');
    for (final d in rule.docs) {
      out.writeln('  $d');
    }
  }
  return out.toString().trimRight();
}
