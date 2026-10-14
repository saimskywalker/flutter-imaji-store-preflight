import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'config.dart';
import 'engine.dart';
import 'finding.dart';
import 'report/machine_reporters.dart';
import 'report/text_reporter.dart';
import 'rules/all_rules.dart';
import 'version.dart';

/// Exit codes of the command-line tool.
abstract final class ExitCodes {
  /// No finding at or above the failure threshold.
  static const ok = 0;

  /// At least one finding at or above the failure threshold.
  static const findings = 1;

  /// Bad arguments, a bad configuration file, or not a Flutter project.
  static const usage = 2;
}

ArgParser _parser() => ArgParser(usageLineLength: 80)
  ..addOption(
    'project',
    abbr: 'p',
    help: 'Flutter project root to check.',
    defaultsTo: '.',
    valueHelp: 'dir',
  )
  ..addOption(
    'config',
    abbr: 'c',
    help:
        'Configuration file. Defaults to $configFileName in the project root, '
        'when present.',
    valueHelp: 'file',
  )
  ..addOption(
    'format',
    abbr: 'f',
    help: 'Output format.',
    allowed: ['text', 'json', 'sarif'],
    defaultsTo: 'text',
  )
  ..addFlag('sarif', negatable: false, help: 'Shorthand for --format sarif.')
  ..addOption(
    'output',
    abbr: 'o',
    help:
        'Write the report to this file instead of stdout '
        '(a one-line summary still goes to stderr).',
    valueHelp: 'file',
  )
  ..addOption(
    'fail-on',
    help:
        'Lowest severity that makes the exit code 1. '
        'Overrides `fail_on` in the configuration (default: error).',
    allowed: ['error', 'warning', 'info', 'never'],
  )
  ..addOption(
    'today',
    help: 'Date that deadlines are measured against, for reproducible runs.',
    valueHelp: 'YYYY-MM-DD',
  )
  ..addFlag(
    'brief',
    negatable: false,
    help: 'Text output without the why/fix explanation under each rule.',
  )
  ..addFlag(
    'color',
    help:
        'Colour text output. Default: when stdout is a terminal and '
        'NO_COLOR is unset.',
  )
  ..addFlag('list-rules', negatable: false, help: 'List every rule and exit.')
  ..addOption(
    'explain',
    help: 'Explain one rule (why it exists, how to fix it) and exit.',
    valueHelp: 'rule-id',
  )
  ..addFlag('version', negatable: false, help: 'Print the version and exit.')
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

/// Runs the command-line tool with [arguments] and returns the exit code.
///
/// [stdoutSink] and [stderrSink] default to the process streams; [workingDir]
/// and [environment] default to the process's. All four exist for tests.
int runCli(
  List<String> arguments, {
  StringSink? stdoutSink,
  StringSink? stderrSink,
  String? workingDir,
  Map<String, String>? environment,
}) {
  final out = stdoutSink ?? stdout;
  final err = stderrSink ?? stderr;
  final cwd = p.normalize(p.absolute(workingDir ?? Directory.current.path));
  final env = environment ?? Platform.environment;
  final parser = _parser();

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    err
      ..writeln(e.message)
      ..writeln()
      ..writeln(_usage(parser));
    return ExitCodes.usage;
  }

  if (args.flag('help')) {
    out.writeln(_usage(parser));
    return ExitCodes.ok;
  }
  if (args.flag('version')) {
    out.writeln('$packageName $packageVersion');
    return ExitCodes.ok;
  }
  if (args.flag('list-rules')) {
    out.writeln(renderRuleList(builtInRules));
    return ExitCodes.ok;
  }
  if (args.option('explain') case final id?) {
    for (final rule in builtInRules) {
      if (rule.id == id) {
        out.writeln(renderExplain(rule));
        return ExitCodes.ok;
      }
    }
    err.writeln('Unknown rule `$id`. Run --list-rules to see them all.');
    return ExitCodes.usage;
  }

  var projectArg = args.option('project')!;
  if (args.rest.length == 1 && projectArg == '.') {
    projectArg = args.rest.single;
  } else if (args.rest.isNotEmpty) {
    err.writeln('Unexpected arguments: ${args.rest.join(' ')}');
    return ExitCodes.usage;
  }
  final root = p.normalize(p.join(cwd, projectArg));
  if (!Directory(root).existsSync()) {
    err.writeln('Project directory not found: $root');
    return ExitCodes.usage;
  }
  final looksLikeFlutter =
      File(p.join(root, 'pubspec.yaml')).existsSync() ||
      Directory(p.join(root, 'ios')).existsSync() ||
      Directory(p.join(root, 'android')).existsSync();
  if (!looksLikeFlutter) {
    err.writeln(
      '$root has no pubspec.yaml, ios/ or android/; pass the Flutter project '
      'root with --project.',
    );
    return ExitCodes.usage;
  }

  PreflightConfig config;
  try {
    final explicit = args.option('config');
    final path = explicit != null
        ? p.join(cwd, explicit)
        : p.join(root, configFileName);
    config = explicit != null || File(path).existsSync()
        ? PreflightConfig.load(path, builtInRules)
        : const PreflightConfig();
  } on ConfigException catch (e) {
    err.writeln('Invalid configuration: $e');
    return ExitCodes.usage;
  }
  if (args.option('fail-on') case final failOn?) {
    config = PreflightConfig(
      rules: config.rules,
      ignores: config.ignores,
      paths: config.paths,
      source: config.source,
      failOn: failOn == 'never' ? null : Severity.tryParse(failOn),
    );
  }

  DateTime? today;
  if (args.option('today') case final value?) {
    today = DateTime.tryParse(value);
    if (today == null) {
      err.writeln('--today must be a date like 2026-08-31, got "$value".');
      return ExitCodes.usage;
    }
  }

  final report = runPreflight(
    root,
    config: config,
    today: today,
    environment: env,
  );

  final relative = p.relative(root, from: cwd);
  final prefix = relative == '.' || relative.startsWith('..')
      ? ''
      : p.split(relative).join('/');
  final format = args.flag('sarif') ? 'sarif' : args.option('format')!;
  final output = args.option('output');
  final color = args.wasParsed('color')
      ? args.flag('color')
      : output == null &&
            stdoutSink == null &&
            stdout.hasTerminal &&
            !env.containsKey('NO_COLOR');
  final rendered = switch (format) {
    'json' => renderJson(report, pathPrefix: prefix),
    'sarif' => renderSarif(report, pathPrefix: prefix),
    _ => renderText(
      report,
      pathPrefix: prefix,
      color: color,
      explain: !args.flag('brief'),
    ),
  };

  if (output != null) {
    try {
      File(p.join(cwd, output))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(rendered.endsWith('\n') ? rendered : '$rendered\n');
    } on FileSystemException catch (e) {
      err.writeln('Cannot write $output: ${e.message}');
      return ExitCodes.usage;
    }
    err.writeln(
      '$packageName: ${report.count(Severity.error)} errors, '
      '${report.count(Severity.warning)} warnings, '
      '${report.count(Severity.info)} info; report written to $output',
    );
  } else {
    out.write(rendered.endsWith('\n') ? rendered : '$rendered\n');
  }
  return report.failed ? ExitCodes.findings : ExitCodes.ok;
}

String _usage(ArgParser parser) =>
    '''
Catch App Store and Google Play rejections in a Flutter project before review.

Usage: $packageName [options] [project-dir]

${parser.usage}

Exit codes: 0 no failing findings, 1 failing findings, 2 usage or configuration error.
Docs: $repositoryUrl''';
