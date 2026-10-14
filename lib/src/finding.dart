/// How serious a finding is.
///
/// Ordered from most to least severe, so `index` comparisons read naturally:
/// a finding "meets" a threshold when its index is at most the threshold's.
enum Severity {
  /// A contradiction that gets builds rejected or features silently broken.
  error,

  /// Probably wrong, or a heuristic that is right most of the time.
  warning,

  /// Worth knowing; never wrong to ignore.
  info;

  /// Whether this severity is at least as severe as [threshold].
  bool meets(Severity threshold) => index <= threshold.index;

  /// Parses `error`, `warning` or `info`; returns `null` for anything else.
  static Severity? tryParse(String value) {
    for (final s in values) {
      if (s.name == value) return s;
    }
    return null;
  }
}

/// One problem a rule found in one place.
class Finding {
  /// Creates a finding.
  const Finding({
    required this.ruleId,
    required this.severity,
    required this.message,
    this.path,
    this.line,
  });

  /// The id of the rule that produced this finding.
  final String ruleId;

  /// How serious it is, after configuration overrides.
  final Severity severity;

  /// What is wrong, specifically, in this project.
  final String message;

  /// Project-relative, `/`-separated path of the file at fault, if any.
  final String? path;

  /// The 1-based line within [path], if known.
  final int? line;

  /// A copy with a different [severity].
  Finding withSeverity(Severity severity) => Finding(
    ruleId: ruleId,
    severity: severity,
    message: message,
    path: path,
    line: line,
  );

  /// `path:line` (or just the path, or `<project>`), for display.
  String get location => switch ((path, line)) {
    (null, _) => '<project>',
    (final String p, null) => p,
    (final String p, final int l) => '$p:$l',
  };

  @override
  String toString() => '$location: ${severity.name}: [$ruleId] $message';
}
