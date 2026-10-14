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

String _sarifLevel(Severity s) => switch (s) {
  Severity.error => 'error',
  Severity.warning => 'warning',
  Severity.info => 'note',
};

/// Renders the report as SARIF 2.1.0 for GitHub code scanning.
///
/// Artifact URIs are relative to `%SRCROOT%`, which is the working directory
/// the tool ran in — run it from the repository root (with `--project` for a
/// Flutter app in a subdirectory) so that GitHub can place annotations.
/// Suppressed findings are included with their justification, which code
/// scanning shows as dismissed rather than dropping them.
String renderSarif(PreflightReport report, {String pathPrefix = ''}) {
  final rules = report.rules;
  final index = {for (var i = 0; i < rules.length; i++) rules[i].id: i};

  Map<String, Object?> result(Finding f, {String? suppression}) {
    final location = <String, Object?>{
      'physicalLocation': {
        'artifactLocation': {
          'uri': displayPath(pathPrefix, f.path ?? 'pubspec.yaml'),
          'uriBaseId': '%SRCROOT%',
        },
        if (f.line != null) 'region': {'startLine': f.line},
      },
    };
    return {
      'ruleId': f.ruleId,
      if (index[f.ruleId] != null) 'ruleIndex': index[f.ruleId],
      'level': _sarifLevel(f.severity),
      'message': {'text': f.message},
      'locations': [location],
      if (suppression != null)
        'suppressions': [
          {'kind': 'external', 'justification': suppression},
        ],
    };
  }

  final sarif = {
    r'$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
    'version': '2.1.0',
    'runs': [
      {
        'tool': {
          'driver': {
            'name': packageName,
            'version': packageVersion,
            'semanticVersion': packageVersion,
            'informationUri': repositoryUrl,
            'rules': [
              for (final r in rules)
                {
                  'id': r.id,
                  'name': r.id,
                  'shortDescription': {'text': r.title},
                  'fullDescription': {'text': r.why},
                  'help': {
                    'text': '${r.why}\n\nHow to fix: ${r.fix}',
                    'markdown':
                        '**Why it matters.** ${r.why}\n\n'
                        '**How to fix.** ${r.fix}\n\n'
                        '${r.docs.map((d) => '- <$d>').join('\n')}',
                  },
                  if (r.docs.isNotEmpty) 'helpUri': r.docs.first,
                  'defaultConfiguration': {
                    'level': _sarifLevel(r.defaultSeverity),
                  },
                  'properties': {
                    'tags': [r.platform.name, 'store-review'],
                  },
                },
            ],
          },
        },
        'results': [
          for (final f in report.findings) result(f),
          for (final s in report.suppressed)
            result(s.finding, suppression: s.entry.reason),
        ],
      },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(sarif);
}
