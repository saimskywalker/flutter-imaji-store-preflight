import 'dart:convert';

import '../engine.dart';
import '../finding.dart';
import '../rule.dart';
import '../version.dart';
import 'paths.dart';

Map<String, Object?> _rule(Rule r) => {
  'id': r.id,
  'title': r.title,
  'platform': r.platform.name,
  'defaultSeverity': r.defaultSeverity.name,
  'why': r.why,
  'fix': r.fix,
  'docs': r.docs,
};

Map<String, Object?> _finding(Finding f, String prefix) => {
  'rule': f.ruleId,
  'severity': f.severity.name,
  'message': f.message,
  'path': f.path == null ? null : displayPath(prefix, f.path!),
  'line': f.line,
};

/// Renders the report as a stable JSON document (schema version 1).
///
/// Paths are relative to the working directory the tool ran in, like the
/// text output, so they can be opened directly.
String renderJson(PreflightReport report, {String pathPrefix = ''}) {
  final json = {
    'schemaVersion': 1,
    'tool': {'name': packageName, 'version': packageVersion},
    'projectRoot': report.projectRoot,
    'failOn': report.failOn?.name,
    'failed': report.failed,
    'summary': {
      for (final s in Severity.values) s.name: report.count(s),
      'suppressed': report.suppressed.length,
    },
    'findings': [for (final f in report.findings) _finding(f, pathPrefix)],
    'suppressed': [
      for (final s in report.suppressed)
        {..._finding(s.finding, pathPrefix), 'reason': s.entry.reason},
    ],
    'disabledRules': [
      for (final d in report.disabled) {'rule': d.rule.id, 'reason': d.reason},
    ],
    'unusedIgnores': [
      for (final e in report.unusedIgnores)
        {'rule': e.rule, 'path': e.path, 'match': e.match, 'reason': e.reason},
    ],
    'rules': [for (final r in report.rules) _rule(r)],
  };
  return const JsonEncoder.withIndent('  ').convert(json);
}
