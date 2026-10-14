// Runs the preflight checks on a Flutter project and prints the report.
//
//   dart run example/main.dart path/to/flutter_app
import 'dart:io';

import 'package:imaji_store_preflight/imaji_store_preflight.dart';

void main(List<String> args) {
  final root = args.isEmpty ? '.' : args.first;
  final configFile = File('$root/$configFileName');
  final config = configFile.existsSync()
      ? PreflightConfig.load(configFile.path, builtInRules)
      : const PreflightConfig();

  final report = runPreflight(root, config: config);
  stdout.write(renderText(report));

  // Or consume findings directly:
  for (final finding in report.findings) {
    if (finding.severity == Severity.error) {
      stderr.writeln('${finding.ruleId} at ${finding.location}');
    }
  }
  exitCode = report.failed ? 1 : 0;
}
