/// Catch App Store and Google Play rejections in a Flutter project before
/// review.
///
/// The command-line tool is the main entry point (`dart run
/// imaji_store_preflight`), but the engine is a library too: load a
/// configuration with `PreflightConfig.load`, run `runPreflight`, and render
/// the `PreflightReport` with `renderText`, `renderJson` or `renderSarif`.
///
/// To write a rule, extend `Rule`; see CONTRIBUTING.md.
library;

export 'src/cli.dart' show ExitCodes, runCli;
export 'src/config.dart';
export 'src/engine.dart';
export 'src/finding.dart';
export 'src/project.dart';
export 'src/report/machine_reporters.dart' show renderJson, renderSarif;
export 'src/report/text_reporter.dart'
    show renderExplain, renderRuleList, renderText;
export 'src/rule.dart';
export 'src/rules/all_rules.dart';
export 'src/version.dart';
