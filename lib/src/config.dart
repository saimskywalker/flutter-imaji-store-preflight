import 'dart:io';

import 'package:yaml/yaml.dart';

import 'finding.dart';
import 'project.dart';
import 'rule.dart';

/// The configuration file name looked up in the project root.
const configFileName = 'imaji_store_preflight.yaml';

/// Thrown for a configuration file that is malformed or breaks a policy
/// (for example, disabling a rule without a reason).
class ConfigException implements Exception {
  /// Creates the exception.
  ConfigException(this.message, {this.path, this.line});

  /// What is wrong.
  final String message;

  /// The configuration file, when known.
  final String? path;

  /// The 1-based line, when known.
  final int? line;

  @override
  String toString() {
    final where = [?path, if (line != null) '$line'].join(':');
    return where.isEmpty ? message : '$where: $message';
  }
}

/// Per-rule configuration.
class RuleConfig {
  /// Creates a rule configuration.
  const RuleConfig({
    this.enabled = true,
    this.reason,
    this.severity,
    this.options = const {},
  });

  /// Whether the rule runs.
  final bool enabled;

  /// Why the rule is disabled. Required when [enabled] is false.
  final String? reason;

  /// Severity that replaces the rule's own for every finding it reports.
  final Severity? severity;

  /// Rule-specific options.
  final Map<String, Object?> options;
}

/// A suppression of specific findings.
class IgnoreEntry {
  /// Creates an ignore entry.
  const IgnoreEntry({
    required this.rule,
    required this.reason,
    this.path,
    this.match,
  });

  /// The rule whose findings are suppressed.
  final String rule;

  /// Why. Required, and shown in every report that lists the suppression.
  final String reason;

  /// Only findings in this project-relative path (exact, or a directory
  /// prefix ending in `/`).
  final String? path;

  /// Only findings whose message contains this text.
  final String? match;

  /// Whether this entry suppresses [finding].
  bool matches(Finding finding) {
    if (finding.ruleId != rule) return false;
    final path = this.path;
    if (path != null) {
      final actual = finding.path;
      if (actual == null) return false;
      if (path.endsWith('/') ? !actual.startsWith(path) : actual != path) {
        return false;
      }
    }
    final match = this.match;
    return match == null || finding.message.contains(match);
  }

  /// A short description used in reports, e.g. `rule @ path ~ "text"`.
  String describe() => [
    rule,
    if (path != null) '@ $path',
    if (match != null) '~ "$match"',
  ].join(' ');
}

/// The whole configuration.
class PreflightConfig {
  /// Creates a configuration; the defaults equal having no file at all.
  const PreflightConfig({
    this.rules = const {},
    this.ignores = const [],
    this.failOn = Severity.error,
    this.paths = const ProjectPaths(),
    this.source,
  });

  /// Configuration by rule id.
  final Map<String, RuleConfig> rules;

  /// Finding suppressions.
  final List<IgnoreEntry> ignores;

  /// The lowest severity that makes the run fail, or `null` for never.
  final Severity? failOn;

  /// Path overrides.
  final ProjectPaths paths;

  /// The file this configuration was read from, if any.
  final String? source;

  /// The configuration for rule [id] (defaults when not configured).
  RuleConfig forRule(String id) => rules[id] ?? const RuleConfig();

  /// Loads [path], validating it against [knownRules].
  static PreflightConfig load(String path, List<Rule> knownRules) {
    final file = File(path);
    if (!file.existsSync()) {
      throw ConfigException('configuration file not found', path: path);
    }
    return parse(file.readAsStringSync(), knownRules, source: path);
  }

  /// Parses configuration [text], validating it against [knownRules].
  static PreflightConfig parse(
    String text,
    List<Rule> knownRules, {
    String? source,
  }) {
    final Object? doc;
    try {
      doc = loadYaml(text, sourceUrl: source == null ? null : Uri.file(source));
    } on YamlException catch (e) {
      throw ConfigException(
        e.message,
        path: source,
        line: e.span == null ? null : e.span!.start.line + 1,
      );
    }
    if (doc == null) return PreflightConfig(source: source);
    if (doc is! YamlMap) {
      throw ConfigException('the top level must be a map', path: source);
    }
    return _Parser(source, {for (final r in knownRules) r.id: r}).parse(doc);
  }
}

class _Parser {
  _Parser(this.source, this.rules);

  final String? source;
  final Map<String, Rule> rules;

  Never fail(String message, [Object? node]) => throw ConfigException(
    message,
    path: source,
    line: node is YamlNode ? node.span.start.line + 1 : null,
  );

  YamlNode nodeOf(YamlMap map, Object key) =>
      map.nodes[key] ?? map.nodes.entries.first.value;

  void allowOnly(YamlMap map, Set<String> keys, String where) {
    for (final key in map.nodes.keys) {
      final name = key is YamlScalar ? key.value : key;
      if (!keys.contains(name)) {
        fail(
          'unknown key `$name` in $where; expected one of '
          '${(keys.toList()..sort()).join(', ')}',
          key,
        );
      }
    }
  }

  String? optString(YamlMap map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      fail('`$key` must be a non-empty string', nodeOf(map, key));
    }
    return value;
  }

  List<String>? optStringList(YamlMap map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is String) return [value];
    if (value is! YamlList || value.any((v) => v is! String)) {
      fail('`$key` must be a string or a list of strings', nodeOf(map, key));
    }
    return value.cast<String>();
  }

  PreflightConfig parse(YamlMap doc) {
    allowOnly(doc, const {'fail_on', 'paths', 'rules', 'ignore'}, 'the file');

    Severity? failOn = Severity.error;
    final failOnValue = doc['fail_on'];
    if (failOnValue != null) {
      if (failOnValue == 'never') {
        failOn = null;
      } else {
        failOn = Severity.tryParse('$failOnValue');
        if (failOn == null) {
          fail(
            '`fail_on` must be error, warning, info or never',
            nodeOf(doc, 'fail_on'),
          );
        }
      }
    }

    return PreflightConfig(
      failOn: failOn,
      paths: _paths(doc),
      rules: _rules(doc),
      ignores: _ignores(doc),
      source: source,
    );
  }

  ProjectPaths _paths(YamlMap doc) {
    final paths = doc['paths'];
    if (paths == null) return const ProjectPaths();
    if (paths is! YamlMap) fail('`paths` must be a map', nodeOf(doc, 'paths'));
    allowOnly(paths, const {
      'info_plist',
      'privacy_manifest',
      'entitlements',
      'export_options',
      'android_manifest',
      'app_gradle',
      'arb_dir',
    }, '`paths`');
    return ProjectPaths(
      infoPlist: optString(paths, 'info_plist'),
      privacyManifest: optString(paths, 'privacy_manifest'),
      entitlements: optStringList(paths, 'entitlements'),
      exportOptions: optStringList(paths, 'export_options'),
      androidManifest: optString(paths, 'android_manifest'),
      appGradle: optString(paths, 'app_gradle'),
      arbDir: optString(paths, 'arb_dir'),
    );
  }

  Map<String, RuleConfig> _rules(YamlMap doc) {
    final section = doc['rules'];
    if (section == null) return const {};
    if (section is! YamlMap) {
      fail('`rules` must be a map', nodeOf(doc, 'rules'));
    }
    final result = <String, RuleConfig>{};
    for (final MapEntry(key: keyNode, value: valueNode)
        in section.nodes.entries) {
      final id = keyNode is YamlScalar ? '${keyNode.value}' : '$keyNode';
      final rule = rules[id];
      if (rule == null) {
        fail('unknown rule `$id` (see `--list-rules`)', keyNode);
      }
      final value = valueNode.value;
      if (value is bool) {
        if (value) {
          result[id] = const RuleConfig();
          continue;
        }
        fail(
          'disabling `$id` needs a reason: write '
          '`$id: {enabled: false, reason: "..."}`',
          valueNode,
        );
      }
      if (valueNode is! YamlMap) {
        fail('`rules.$id` must be a map or `true`', valueNode);
      }
      allowOnly(valueNode, {
        'enabled',
        'reason',
        'severity',
        ...rule.optionKeys,
      }, '`rules.$id`');
      final enabled = valueNode['enabled'] ?? true;
      if (enabled is! bool) {
        fail('`enabled` must be true or false', nodeOf(valueNode, 'enabled'));
      }
      final reason = optString(valueNode, 'reason');
      if (!enabled && reason == null) {
        fail(
          'disabling `$id` needs a non-empty `reason`, so the next person '
          'knows why the check is off',
          valueNode,
        );
      }
      Severity? severity;
      if (valueNode['severity'] != null) {
        severity = Severity.tryParse('${valueNode['severity']}');
        if (severity == null) {
          fail(
            '`severity` must be error, warning or info',
            nodeOf(valueNode, 'severity'),
          );
        }
      }
      final options = <String, Object?>{
        for (final key in rule.optionKeys)
          if (valueNode.containsKey(key)) key: _plain(valueNode[key]),
      };
      if (options.isNotEmpty) {
        final error = rule.validateOptions(options);
        if (error != null) fail('`rules.$id`: $error', valueNode);
      }
      result[id] = RuleConfig(
        enabled: enabled,
        reason: reason,
        severity: severity,
        options: options,
      );
    }
    return result;
  }

  List<IgnoreEntry> _ignores(YamlMap doc) {
    final section = doc['ignore'];
    if (section == null) return const [];
    if (section is! YamlList) {
      fail('`ignore` must be a list', nodeOf(doc, 'ignore'));
    }
    final entries = <IgnoreEntry>[];
    for (final node in section.nodes) {
      if (node is! YamlMap) fail('each `ignore` entry must be a map', node);
      entries.add(_ignore(node));
    }
    return entries;
  }

  IgnoreEntry _ignore(YamlMap node) {
    allowOnly(node, const {'rule', 'path', 'match', 'reason'}, '`ignore`');
    final rule = optString(node, 'rule');
    if (rule == null) fail('an `ignore` entry needs `rule`', node);
    if (!rules.containsKey(rule)) {
      fail('unknown rule `$rule` in `ignore`', nodeOf(node, 'rule'));
    }
    final reason = optString(node, 'reason');
    if (reason == null) {
      fail(
        'an `ignore` entry needs a non-empty `reason`, so the next person '
        'knows why the finding is accepted',
        node,
      );
    }
    return IgnoreEntry(
      rule: rule,
      reason: reason,
      path: optString(node, 'path'),
      match: optString(node, 'match'),
    );
  }

  /// Converts YAML collections into plain Dart ones so rules never depend on
  /// `package:yaml` types.
  static Object? _plain(Object? value) => switch (value) {
    final YamlMap m => {for (final e in m.entries) '${e.key}': _plain(e.value)},
    final YamlList l => [for (final v in l) _plain(v)],
    _ => value,
  };
}
