import 'config.dart';
import 'finding.dart';
import 'project.dart';
import 'rule.dart';
import 'rules/all_rules.dart';

/// A finding that an `ignore` entry suppressed.
class SuppressedFinding {
  /// Creates a record of a suppression.
  const SuppressedFinding(this.finding, this.entry);

  /// The finding as the rule reported it.
  final Finding finding;

  /// The configuration entry that suppressed it.
  final IgnoreEntry entry;
}

/// A rule that did not run because the configuration disabled it.
class DisabledRule {
  /// Creates a record of a disabled rule.
  const DisabledRule(this.rule, this.reason);

  /// The rule.
  final Rule rule;

  /// The reason the configuration gives.
  final String reason;
}

/// The outcome of a run.
class PreflightReport {
  /// Creates a report.
  const PreflightReport({
    required this.projectRoot,
    required this.rules,
    required this.findings,
    required this.suppressed,
    required this.disabled,
    required this.unusedIgnores,
    required this.failOn,
  });

  /// Absolute path of the project that was checked.
  final String projectRoot;

  /// The rules that ran.
  final List<Rule> rules;

  /// Active findings, in rule order.
  final List<Finding> findings;

  /// Findings an `ignore` entry suppressed.
  final List<SuppressedFinding> suppressed;

  /// Rules the configuration turned off.
  final List<DisabledRule> disabled;

  /// `ignore` entries that matched nothing — candidates for deletion.
  final List<IgnoreEntry> unusedIgnores;

  /// The failure threshold in effect, or `null` for never.
  final Severity? failOn;

  /// Number of active findings with [severity].
  int count(Severity severity) =>
      findings.where((f) => f.severity == severity).length;

  /// Whether any active finding meets [failOn].
  bool get failed {
    final threshold = failOn;
    return threshold != null &&
        findings.any((f) => f.severity.meets(threshold));
  }

  /// The rule with [id], whether it ran or was disabled.
  Rule? ruleById(String id) {
    for (final r in [...rules, ...disabled.map((d) => d.rule)]) {
      if (r.id == id) return r;
    }
    return null;
  }
}

/// Checks the Flutter project at [projectRoot].
///
/// [today] fixes the date deadline rules measure against (default: now, in
/// UTC). [rules] replaces the built-in rule set, which is mostly useful in
/// tests. [environment] is passed to [Project.load].
PreflightReport runPreflight(
  String projectRoot, {
  PreflightConfig config = const PreflightConfig(),
  DateTime? today,
  List<Rule> rules = builtInRules,
  Map<String, String>? environment,
}) {
  final project = Project.load(
    projectRoot,
    paths: config.paths,
    environment: environment,
  );
  final now = today ?? DateTime.now().toUtc();
  final day = DateTime.utc(now.year, now.month, now.day);

  final ran = <Rule>[];
  final disabled = <DisabledRule>[];
  final findings = <Finding>[];
  final suppressed = <SuppressedFinding>[];
  final usedIgnores = <IgnoreEntry>{};

  for (final rule in rules) {
    final ruleConfig = config.forRule(rule.id);
    if (!ruleConfig.enabled) {
      disabled.add(DisabledRule(rule, ruleConfig.reason ?? ''));
      continue;
    }
    ran.add(rule);
    final context = RuleContext(
      project: project,
      options: ruleConfig.options,
      today: day,
    );
    for (var finding in rule.check(context)) {
      if (ruleConfig.severity case final severity?) {
        finding = finding.withSeverity(severity);
      }
      IgnoreEntry? entry;
      for (final candidate in config.ignores) {
        if (candidate.matches(finding)) {
          entry = candidate;
          break;
        }
      }
      if (entry == null) {
        findings.add(finding);
      } else {
        usedIgnores.add(entry);
        suppressed.add(SuppressedFinding(finding, entry));
      }
    }
  }

  return PreflightReport(
    projectRoot: project.root,
    rules: ran,
    findings: findings,
    suppressed: suppressed,
    disabled: disabled,
    unusedIgnores: [
      for (final e in config.ignores)
        if (!usedIgnores.contains(e)) e,
    ],
    failOn: config.failOn,
  );
}
