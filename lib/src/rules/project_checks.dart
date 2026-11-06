import '../finding.dart';
import '../plist.dart';
import '../rule.dart';
import '../xml_tree.dart';

/// The prefix of every project check's rule id, e.g. `check:no-backup`.
///
/// The colon keeps project checks from ever colliding with a built-in rule
/// id, which is kebab-case.
const checkRulePrefix = 'check:';

/// The file a project check reads.
enum CheckFile {
  /// The app's `Info.plist` (`paths.info_plist`).
  infoPlist('info_plist'),

  /// The app's main `AndroidManifest.xml` (`paths.android_manifest`).
  androidManifest('android_manifest');

  const CheckFile(this.key);

  /// How the file is named under `file:` in the configuration.
  final String key;
}

/// What a project check asserts about its value.
enum CheckOperator {
  /// The value is present.
  exists('exists'),

  /// The value is not present.
  absent('absent'),

  /// The value is present and equal to the expected one.
  equals('equals'),

  /// The value is absent, or present and equal to the expected one.
  absentOrEquals('absent_or_equals'),

  /// The value is absent, or present and different from the expected one.
  notEquals('not_equals'),

  /// The array (Info.plist) or the attribute values of every matching element
  /// (AndroidManifest) contain each listed value.
  contains('contains'),

  /// The value, an array item, or a matching element's attribute is none of
  /// the listed values.
  noneOf('none_of'),

  /// The value is a string the regular expression matches.
  matches('matches');

  const CheckOperator(this.key);

  /// How the operator is written in the configuration.
  final String key;
}

/// A project-specific invariant from the `checks:` section of the
/// configuration, run like any other rule under the id `check:<name>`.
///
/// The configuration parser validates every field, so the constructor
/// trusts its arguments: [expected] is `true` for [CheckOperator.exists] and
/// [CheckOperator.absent], a [RegExp] for [CheckOperator.matches], a
/// non-empty `List<Object>` of strings, booleans or numbers for
/// [CheckOperator.contains] and [CheckOperator.noneOf], and otherwise a
/// string, boolean, number or such a list (Info.plist) or a string
/// (AndroidManifest).
class ProjectCheckRule extends Rule {
  /// Creates a check.
  ProjectCheckRule({
    required this.name,
    required this.file,
    required this.operator,
    required this.expected,
    required this.reason,
    this.keyPath = const [],
    this.element = '',
    this.attribute = '',
    this.severity = Severity.error,
  });

  /// The check's name under `checks:`.
  final String name;

  /// The file the check reads.
  final CheckFile file;

  /// For [CheckFile.infoPlist]: the key, one segment per nested dictionary.
  final List<String> keyPath;

  /// For [CheckFile.androidManifest]: the element name, e.g. `application`.
  final String element;

  /// For [CheckFile.androidManifest]: the attribute's qualified name, e.g.
  /// `android:allowBackup`.
  final String attribute;

  /// The assertion.
  final CheckOperator operator;

  /// The operand; see the class documentation.
  final Object expected;

  /// Why the value is pinned. Shown as the rule's [why].
  final String reason;

  /// The severity of every finding (default [Severity.error]).
  final Severity severity;

  @override
  String get id => '$checkRulePrefix$name';

  @override
  String get title => '${_subject()} ${_expectation()}';

  @override
  RulePlatform get platform => switch (file) {
    CheckFile.infoPlist => RulePlatform.ios,
    CheckFile.androidManifest => RulePlatform.android,
  };

  @override
  Severity get defaultSeverity => severity;

  @override
  String get why => reason;

  @override
  String get fix =>
      'Change the app so that ${_subject()} ${_expectation()}. If the pin '
      'itself is out of date, update `checks.$name` in the configuration '
      'file, and its reason with it.';

  @override
  List<String> get docs => const [];

  String _subject() => switch (file) {
    CheckFile.infoPlist => 'Info.plist `${keyPath.join('.')}`',
    CheckFile.androidManifest => '<$element $attribute>',
  };

  String _expectation() => switch (operator) {
    CheckOperator.exists => 'is present',
    CheckOperator.absent => 'is absent',
    CheckOperator.equals => 'equals ${_show(expected)}',
    CheckOperator.absentOrEquals => 'is absent or equals ${_show(expected)}',
    CheckOperator.notEquals => 'does not equal ${_show(expected)}',
    CheckOperator.contains => 'contains ${_showEach(expected)}',
    CheckOperator.noneOf => 'is none of ${_showEach(expected)}',
    CheckOperator.matches => 'matches /${(expected as RegExp).pattern}/',
  };

  @override
  Iterable<Finding> check(RuleContext context) {
    final project = context.project;
    final (path, configKey) = switch (file) {
      CheckFile.infoPlist => (project.infoPlistPath, 'paths.info_plist'),
      CheckFile.androidManifest => (
        project.androidManifestPath,
        'paths.android_manifest',
      ),
    };
    final loaded = switch (file) {
      CheckFile.infoPlist => project.infoPlist != null,
      CheckFile.androidManifest => project.androidManifest != null,
    };
    if (!loaded) {
      // An unreadable file is reported once, by `unreadable-file`.
      if (project.problems.any((problem) => problem.path == path)) return [];
      return [
        finding(
          '$path does not exist, so this check cannot run. Set `$configKey` '
          'if the file is somewhere else.',
        ),
      ];
    }
    return switch (file) {
      CheckFile.infoPlist => _checkPlist(path, project.infoPlist!.root),
      CheckFile.androidManifest => _checkManifest(
        path,
        project.androidManifest!.root,
      ),
    };
  }

  // Info.plist ---------------------------------------------------------------

  /// Looks up [keyPath]. Returns the value and the line of its key, or `null`
  /// and the line of the deepest parent that exists.
  (PlistValue?, int) _lookup(PlistDict root) {
    var dict = root;
    var parentLine = root.line;
    for (var i = 0; i < keyPath.length; i++) {
      final key = keyPath[i];
      final value = dict[key];
      if (value == null) return (null, parentLine);
      final line = dict.lineOf(key);
      if (i == keyPath.length - 1) return (value, line);
      if (value is! PlistDict) return (null, line);
      dict = value;
      parentLine = line;
    }
    return (null, parentLine);
  }

  Iterable<Finding> _checkPlist(String path, PlistDict root) sync* {
    final (value, line) = _lookup(root);
    final key = '`${keyPath.join('.')}`';
    Finding at(String message, [int? where]) =>
        finding(message, path: path, line: where ?? line);

    if (value == null) {
      switch (operator) {
        case CheckOperator.exists:
          yield at('$key is missing.');
        case CheckOperator.equals:
          yield at('$key is missing; expected ${_show(expected)}.');
        case CheckOperator.contains:
          yield at(
            '$key is missing; expected an array containing '
            '${_showEach(expected)}.',
          );
        case CheckOperator.matches:
          yield at(
            '$key is missing; expected a string matching '
            '/${(expected as RegExp).pattern}/.',
          );
        case CheckOperator.absent ||
            CheckOperator.absentOrEquals ||
            CheckOperator.notEquals ||
            CheckOperator.noneOf:
          break;
      }
      return;
    }

    final actual = _showPlist(value);
    switch (operator) {
      case CheckOperator.exists:
        break;
      case CheckOperator.absent:
        yield at('$key is present ($actual); expected it to be absent.');
      case CheckOperator.equals || CheckOperator.absentOrEquals:
        if (!_plistEquals(expected, value)) {
          yield at('$key is $actual; expected ${_show(expected)}.');
        }
      case CheckOperator.notEquals:
        if (_plistEquals(expected, value)) {
          yield at('$key is $actual, which this check forbids.');
        }
      case CheckOperator.contains:
        if (value is! PlistArray) {
          yield at('$key is $actual, not an array.');
          break;
        }
        for (final wanted in expected as List<Object>) {
          if (!value.items.any((item) => _scalarEquals(wanted, item))) {
            yield at('$key does not contain ${_show(wanted)}.');
          }
        }
      case CheckOperator.noneOf:
        final forbidden = expected as List<Object>;
        if (value is PlistArray) {
          for (final item in value.items) {
            if (forbidden.any((f) => _scalarEquals(f, item))) {
              yield at(
                '$key contains ${_showPlist(item)}, which this check '
                'forbids.',
                item.line,
              );
            }
          }
        } else if (forbidden.any((f) => _scalarEquals(f, value))) {
          yield at('$key is $actual, which this check forbids.');
        }
      case CheckOperator.matches:
        final pattern = expected as RegExp;
        if (value is! PlistString) {
          yield at('$key is $actual, not a string.');
        } else if (!pattern.hasMatch(value.value)) {
          yield at(
            '$key is $actual, which does not match /${pattern.pattern}/.',
          );
        }
    }
  }

  // AndroidManifest ----------------------------------------------------------

  Iterable<Finding> _checkManifest(String path, XmlNode root) sync* {
    final matching = <(XmlNode, XmlNode)>[];
    void walk(XmlNode node, XmlNode parent) {
      if (node.name == element) matching.add((node, parent));
      for (final child in node.children) {
        walk(child, node);
      }
    }

    walk(root, root);
    Finding at(String message, int line) =>
        finding(message, path: path, line: line);
    final tag = '<$element>';

    if (matching.isEmpty) {
      switch (operator) {
        case CheckOperator.exists ||
            CheckOperator.equals ||
            CheckOperator.contains ||
            CheckOperator.matches:
          yield at(
            'The manifest has no $tag element; expected one whose '
            '$attribute ${_expectation()}.',
            root.line,
          );
        case CheckOperator.absent ||
            CheckOperator.absentOrEquals ||
            CheckOperator.notEquals ||
            CheckOperator.noneOf:
          break;
      }
      return;
    }

    String has(String value) => '$tag has $attribute="$value"';
    switch (operator) {
      case CheckOperator.exists:
        if (!matching.any((m) => m.$1.attributes.containsKey(attribute))) {
          yield at('No $tag sets $attribute.', matching.first.$1.line);
        }
      case CheckOperator.absent:
        for (final (node, _) in matching) {
          if (node.attributes[attribute] case final value?) {
            yield at(
              '${has(value)}; expected it to be absent.',
              node.lineOf(attribute),
            );
          }
        }
      case CheckOperator.equals || CheckOperator.absentOrEquals:
        for (final (node, _) in matching) {
          final value = node.attributes[attribute];
          if (value == null) {
            if (operator == CheckOperator.equals) {
              yield at(
                '$tag has no $attribute; expected ${_show(expected)}.',
                node.line,
              );
            }
          } else if (value != expected) {
            yield at(
              '${has(value)}; expected ${_show(expected)}.',
              node.lineOf(attribute),
            );
          }
        }
      case CheckOperator.notEquals:
        for (final (node, _) in matching) {
          if (node.attributes[attribute] case final value?
              when value == expected) {
            yield at(
              '${has(value)}, which this check forbids.',
              node.lineOf(attribute),
            );
          }
        }
      case CheckOperator.contains:
        final present = {
          for (final (node, _) in matching) ?node.attributes[attribute],
        };
        for (final wanted in expected as List<Object>) {
          if (!present.contains(wanted)) {
            yield at(
              'No $tag has $attribute="$wanted".',
              matching.first.$2.line,
            );
          }
        }
      case CheckOperator.noneOf:
        final forbidden = expected as List<Object>;
        for (final (node, _) in matching) {
          if (node.attributes[attribute] case final value?
              when forbidden.contains(value)) {
            yield at(
              '${has(value)}, which this check forbids.',
              node.lineOf(attribute),
            );
          }
        }
      case CheckOperator.matches:
        final pattern = expected as RegExp;
        for (final (node, _) in matching) {
          final value = node.attributes[attribute];
          if (value == null) {
            yield at(
              '$tag has no $attribute; expected a value matching '
              '/${pattern.pattern}/.',
              node.line,
            );
          } else if (!pattern.hasMatch(value)) {
            yield at(
              '${has(value)}, which does not match /${pattern.pattern}/.',
              node.lineOf(attribute),
            );
          }
        }
    }
  }
}

bool _scalarEquals(Object expected, PlistValue actual) =>
    switch ((expected, actual)) {
      (final bool e, PlistBool(:final value)) => e == value,
      (final String e, PlistString(:final value)) => e == value,
      (final num e, PlistNumber(:final value)) => e == value,
      _ => false,
    };

/// Whether [actual] equals [expected]. A list equals an array with the same
/// items in any order.
bool _plistEquals(Object expected, PlistValue actual) {
  if (expected is! List<Object>) return _scalarEquals(expected, actual);
  if (actual is! PlistArray || actual.items.length != expected.length) {
    return false;
  }
  final remaining = [...actual.items];
  for (final wanted in expected) {
    final i = remaining.indexWhere((item) => _scalarEquals(wanted, item));
    if (i < 0) return false;
    remaining.removeAt(i);
  }
  return true;
}

String _show(Object value) => switch (value) {
  final String s => '"$s"',
  final List<Object> l => '[${l.map(_show).join(', ')}]',
  _ => '$value',
};

String _showEach(Object values) =>
    (values as List<Object>).map(_show).join(', ');

String _showPlist(PlistValue value) => switch (value) {
  PlistString(:final value) => '"$value"',
  PlistBool(:final value) => '$value',
  PlistNumber(:final value) => '$value',
  PlistArray(:final items) => '[${items.map(_showPlist).join(', ')}]',
  PlistDict() => 'a dictionary',
  PlistOpaque(:final kind) => 'a <$kind>',
};
