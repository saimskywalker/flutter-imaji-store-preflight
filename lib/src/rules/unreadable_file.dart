import '../finding.dart';
import '../rule.dart';

/// Configuration files exist in a form this tool (and a reviewer) can read.
class UnreadableFileRule extends Rule {
  /// Creates the rule.
  const UnreadableFileRule();

  @override
  String get id => 'unreadable-file';

  @override
  String get title => 'Store-facing configuration files can be parsed';

  @override
  RulePlatform get platform => RulePlatform.general;

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  String get why =>
      'A file that cannot be parsed cannot be checked, so every other rule '
      'would silently pass it. Malformed XML in Info.plist or the Android '
      'manifest also fails the native build or, worse, is accepted by a '
      'lenient tool and shipped with a different meaning than intended.';

  @override
  String get fix =>
      'Fix the syntax error at the reported line. Binary property lists are '
      'valid for Xcode but opaque in code review; convert them with '
      '`plutil -convert xml1 <file>`.';

  @override
  List<String> get docs => const [
    'https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/PropertyLists/UnderstandXMLPlist/UnderstandXMLPlist.html',
  ];

  @override
  Iterable<Finding> check(RuleContext context) => [
    for (final problem in context.project.problems)
      finding(
        '${problem.path} ${problem.message}',
        path: problem.path,
        line: problem.line,
      ),
  ];
}
