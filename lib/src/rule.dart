import 'finding.dart';
import 'project.dart';

/// The platform a rule is about. Used for grouping in docs and `--list-rules`.
enum RulePlatform {
  /// App Store / iOS configuration.
  ios,

  /// Google Play / Android configuration.
  android,

  /// Both stores, or the project as a whole.
  general,
}

/// What a rule gets to look at when it runs.
class RuleContext {
  /// Creates a context.
  RuleContext({
    required this.project,
    required this.options,
    required this.today,
  });

  /// The loaded project.
  final Project project;

  /// Rule-specific options from the configuration file, already validated
  /// by [Rule.validateOptions]. Empty when none were given.
  final Map<String, Object?> options;

  /// The date deadlines are measured against. Injected so that results are
  /// reproducible in tests and in CI.
  final DateTime today;
}

/// A single check.
///
/// Every rule must be able to explain itself without the source code at hand:
/// [why] names the rejection or silent failure it prevents, [fix] says what to
/// change, and [docs] links the public documentation the rule is built on.
abstract class Rule {
  /// Const constructor for subclasses.
  const Rule();

  /// Stable, kebab-case identifier used in configuration and output.
  String get id;

  /// One-line summary of what the rule checks.
  String get title;

  /// The platform the rule concerns.
  RulePlatform get platform;

  /// Severity used unless the configuration overrides it.
  Severity get defaultSeverity;

  /// Which rejection or silent failure this rule prevents, and why.
  String get why;

  /// How to fix a finding.
  String get fix;

  /// Public documentation the rule is based on.
  List<String> get docs;

  /// Option keys the rule accepts under `rules.<id>:` in the config.
  Set<String> get optionKeys => const {};

  /// Returns a message describing what is wrong with [options], or `null`
  /// when they are acceptable. Only called with keys in [optionKeys].
  String? validateOptions(Map<String, Object?> options) => null;

  /// Runs the check.
  Iterable<Finding> check(RuleContext context);

  /// Builds a finding attributed to this rule.
  Finding finding(
    String message, {
    String? path,
    int? line,
    Severity? severity,
  }) => Finding(
    ruleId: id,
    severity: severity ?? defaultSeverity,
    message: message,
    path: path,
    line: line,
  );
}

/// Helpers for validating option values in [Rule.validateOptions].
abstract final class OptionChecks {
  /// Message if [value] is not a list of non-empty strings.
  static String? stringList(String key, Object? value) {
    if (value is List && value.every((v) => v is String && v.isNotEmpty)) {
      return null;
    }
    return '`$key` must be a list of non-empty strings';
  }

  /// Message if [value] is not a map from strings to non-empty strings.
  static String? stringMap(String key, Object? value) {
    if (value is Map &&
        value.entries.every(
          (e) =>
              e.key is String &&
              e.value is String &&
              (e.value as String).trim().isNotEmpty,
        )) {
      return null;
    }
    return '`$key` must map each entry to a non-empty string';
  }

  /// Message if [value] is not a map from strings to lists of strings.
  static String? stringListMap(String key, Object? value) {
    if (value is Map &&
        value.entries.every(
          (e) =>
              e.key is String &&
              e.value is List &&
              (e.value as List).every((v) => v is String),
        )) {
      return null;
    }
    return '`$key` must map each entry to a list of strings';
  }
}
