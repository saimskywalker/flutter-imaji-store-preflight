import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'plist.dart';
import 'xml_tree.dart';

/// A file the project carries that could not be read, and why.
class FileProblem {
  /// Creates a problem record.
  const FileProblem(this.path, this.message, [this.line]);

  /// Project-relative path, `/`-separated.
  final String path;

  /// What is wrong with it.
  final String message;

  /// The 1-based line, when known.
  final int? line;
}

/// A parsed property list together with where it came from.
class PlistFile {
  /// Creates a record of a parsed property list.
  const PlistFile(this.path, this.root);

  /// Project-relative path, `/`-separated.
  final String path;

  /// The root dictionary.
  final PlistDict root;
}

/// A parsed XML document together with where it came from.
class XmlFile {
  /// Creates a record of a parsed XML document.
  const XmlFile(this.path, this.root);

  /// Project-relative path, `/`-separated.
  final String path;

  /// The root element.
  final XmlNode root;
}

/// A text file (Gradle scripts, Xcode project) together with where it came
/// from.
class TextFile {
  /// Creates a record of a text file.
  const TextFile(this.path, this.text);

  /// Project-relative path, `/`-separated.
  final String path;

  /// The file's contents.
  final String text;

  /// The 1-based line on which [match] starts.
  int lineOf(Match match) => lineAt(match.start);

  /// The 1-based line containing [offset].
  int lineAt(int offset) =>
      '\n'.allMatches(text.substring(0, offset.clamp(0, text.length))).length +
      1;
}

/// How a package arrived in the dependency graph, as `pubspec.lock` says.
enum DependencyKind {
  /// Listed under `dependencies:`.
  directMain,

  /// Listed under `dev_dependencies:`. Not linked into the app.
  directDev,

  /// Listed under `dependency_overrides:`.
  directOverridden,

  /// Pulled in by another package.
  transitive,
}

/// Paths a configuration can override. Every value is project-relative.
class ProjectPaths {
  /// Creates a set of path overrides; `null` means "use the default".
  const ProjectPaths({
    this.infoPlist,
    this.privacyManifest,
    this.entitlements,
    this.exportOptions,
    this.androidManifest,
    this.appGradle,
    this.arbDir,
  });

  /// `ios/Runner/Info.plist` by default.
  final String? infoPlist;

  /// `ios/Runner/PrivacyInfo.xcprivacy` by default.
  final String? privacyManifest;

  /// Every `*.entitlements` directly in `ios/Runner` by default.
  final List<String>? entitlements;

  /// Every `ExportOptions*.plist` found outside build output by default.
  final List<String>? exportOptions;

  /// `android/app/src/main/AndroidManifest.xml` by default.
  final String? androidManifest;

  /// `android/app/build.gradle.kts`, else `android/app/build.gradle`.
  final String? appGradle;

  /// `arb-dir` from `l10n.yaml`, else `lib/l10n`.
  final String? arbDir;
}

/// Directories never searched: build output, dependency caches, VCS data.
const _skippedDirs = {
  '.dart_tool',
  '.git',
  '.gradle',
  '.symlinks',
  'build',
  'DerivedData',
  'Pods',
  'node_modules',
  'ephemeral',
};

/// Everything the rules read from a Flutter project, loaded once.
///
/// Missing files are `null`; files that exist but cannot be parsed are also
/// `null` and are recorded in [problems], so a rule never has to tell the two
/// apart and an unreadable file is still reported exactly once.
class Project {
  Project._(this.root, this.environment);

  /// Loads the project rooted at [rootPath].
  ///
  /// [environment] defaults to [Platform.environment] and is only consulted
  /// for `FLUTTER_ROOT`.
  factory Project.load(
    String rootPath, {
    ProjectPaths paths = const ProjectPaths(),
    Map<String, String>? environment,
  }) {
    final project = Project._(
      p.normalize(p.absolute(rootPath)),
      environment ?? Platform.environment,
    );
    project._load(paths);
    return project;
  }

  /// Absolute, normalised project root.
  final String root;

  /// Environment variables used for SDK discovery.
  final Map<String, String> environment;

  /// Files that exist but could not be read.
  final List<FileProblem> problems = [];

  /// `pubspec.yaml`, when present and readable.
  YamlMap? pubspec;

  /// Packages from `pubspec.lock`, when present: name to how it was pulled in.
  Map<String, DependencyKind>? lockedPackages;

  /// `ios/Runner/Info.plist`.
  PlistFile? infoPlist;

  /// The app's privacy manifest.
  PlistFile? privacyManifest;

  /// Entitlements files, in path order.
  final List<PlistFile> entitlements = [];

  /// Export options property lists, in path order.
  final List<PlistFile> exportOptions = [];

  /// `ios/Runner.xcodeproj/project.pbxproj`.
  TextFile? xcodeProject;

  /// The main Android manifest.
  XmlFile? androidManifest;

  /// The app module's Gradle script.
  TextFile? appGradle;

  /// `android/settings.gradle(.kts)`.
  TextFile? settingsGradle;

  /// `android/build.gradle(.kts)`.
  TextFile? rootGradle;

  /// The ARB directory (project-relative), whether or not it exists.
  late String arbDir;

  /// ARB files found in [arbDir]: project-relative path to locale.
  final Map<String, String> arbLocales = {};

  /// `.lproj` directory names directly in `ios/Runner`, without extension.
  final Set<String> lprojLocales = {};

  /// Whether the project has an `ios/` directory.
  bool get hasIos => Directory(abs('ios')).existsSync();

  /// Whether the project has an `android/` directory.
  bool get hasAndroid => Directory(abs('android')).existsSync();

  /// Absolute path for a project-relative [relative] path.
  String abs(String relative) => p.join(root, p.joinAll(relative.split('/')));

  /// Project-relative, `/`-separated form of an absolute [absolute] path.
  String rel(String absolute) =>
      p.split(p.relative(absolute, from: root)).join('/');

  /// Names of packages linked into the app: everything in `pubspec.lock`
  /// except direct dev dependencies, or — without a lock file — the
  /// `dependencies:` of `pubspec.yaml`.
  late final Set<String> linkedPackages = () {
    final lock = lockedPackages;
    if (lock != null) {
      return {
        for (final MapEntry(:key, :value) in lock.entries)
          if (value != DependencyKind.directDev) key,
      };
    }
    final deps = pubspec?['dependencies'];
    return deps is YamlMap ? deps.keys.whereType<String>().toSet() : <String>{};
  }();

  /// Whether [package] is linked into the app.
  bool links(String package) => linkedPackages.contains(package);

  /// The Flutter SDK root, from `.dart_tool/package_config.json`'s
  /// `flutterRoot` or the `FLUTTER_ROOT` environment variable.
  late final String? flutterRoot = () {
    final config = File(abs('.dart_tool/package_config.json'));
    if (config.existsSync()) {
      try {
        final json = jsonDecode(config.readAsStringSync());
        if (json is Map && json['flutterRoot'] is String) {
          return Uri.parse(json['flutterRoot'] as String).toFilePath();
        }
      } on FormatException {
        // Fall through to the environment.
      }
    }
    return environment['FLUTTER_ROOT'];
  }();

  void _load(ProjectPaths paths) {
    pubspec = _yaml('pubspec.yaml');
    _loadLock();

    infoPlist = _plist(paths.infoPlist ?? 'ios/Runner/Info.plist');
    privacyManifest = _plist(
      paths.privacyManifest ?? 'ios/Runner/PrivacyInfo.xcprivacy',
    );
    for (final path in paths.entitlements ?? _defaultEntitlements()) {
      final file = _plist(path);
      if (file != null) entitlements.add(file);
    }
    for (final path in paths.exportOptions ?? _defaultExportOptions()) {
      final file = _plist(path);
      if (file != null) exportOptions.add(file);
    }
    xcodeProject = _text('ios/Runner.xcodeproj/project.pbxproj');

    final manifestPath =
        paths.androidManifest ?? 'android/app/src/main/AndroidManifest.xml';
    final manifestText = _read(manifestPath);
    if (manifestText != null) {
      try {
        androidManifest = XmlFile(manifestPath, parseXmlTree(manifestText));
      } on XmlTreeException catch (e) {
        problems.add(
          FileProblem(
            manifestPath,
            'is not well-formed XML: ${e.message}',
            e.line,
          ),
        );
      }
    }
    appGradle = paths.appGradle != null
        ? _text(paths.appGradle!)
        : _text('android/app/build.gradle.kts') ??
              _text('android/app/build.gradle');
    settingsGradle =
        _text('android/settings.gradle.kts') ??
        _text('android/settings.gradle');
    rootGradle =
        _text('android/build.gradle.kts') ?? _text('android/build.gradle');

    arbDir = paths.arbDir ?? _arbDirFromL10nYaml() ?? 'lib/l10n';
    _loadArb();
    final runner = Directory(abs('ios/Runner'));
    if (runner.existsSync()) {
      for (final entity in runner.listSync()) {
        if (entity is Directory && entity.path.endsWith('.lproj')) {
          final name = p.basenameWithoutExtension(entity.path);
          if (name != 'Base') lprojLocales.add(name);
        }
      }
    }
  }

  String? _read(String relative) {
    final file = File(abs(relative));
    if (!file.existsSync()) return null;
    try {
      return file.readAsStringSync();
    } on FileSystemException catch (e) {
      problems.add(FileProblem(relative, 'cannot be read: ${e.message}'));
      return null;
    }
  }

  TextFile? _text(String relative) {
    final text = _read(relative);
    return text == null ? null : TextFile(relative, text);
  }

  YamlMap? _yaml(String relative) {
    final text = _read(relative);
    if (text == null) return null;
    try {
      final doc = loadYaml(text);
      return doc is YamlMap ? doc : null;
    } on YamlException catch (e) {
      problems.add(
        FileProblem(
          relative,
          'is not valid YAML: ${e.message}',
          e.span == null ? null : e.span!.start.line + 1,
        ),
      );
      return null;
    }
  }

  PlistFile? _plist(String relative) {
    final file = File(abs(relative));
    if (!file.existsSync()) return null;
    try {
      final value = parsePlistBytes(file.readAsBytesSync());
      if (value is! PlistDict) {
        problems.add(
          FileProblem(relative, 'must have a <dict> at its root', value.line),
        );
        return null;
      }
      return PlistFile(relative, value);
    } on PlistFormatException catch (e) {
      problems.add(FileProblem(relative, e.message, e.line));
      return null;
    } on FileSystemException catch (e) {
      problems.add(FileProblem(relative, 'cannot be read: ${e.message}'));
      return null;
    }
  }

  void _loadLock() {
    final lock = _yaml('pubspec.lock');
    if (lock == null) return;
    final packages = lock['packages'];
    if (packages is! YamlMap) return;
    lockedPackages = {
      for (final MapEntry(:key, :value) in packages.entries)
        if (key is String && value is YamlMap)
          key: switch (value['dependency']) {
            'direct main' => DependencyKind.directMain,
            'direct dev' => DependencyKind.directDev,
            'direct overridden' => DependencyKind.directOverridden,
            _ => DependencyKind.transitive,
          },
    };
  }

  List<String> _defaultEntitlements() {
    final dir = Directory(abs('ios/Runner'));
    if (!dir.existsSync()) return const [];
    return [
      for (final e in dir.listSync())
        if (e is File && e.path.endsWith('.entitlements')) rel(e.path),
    ]..sort();
  }

  List<String> _defaultExportOptions() {
    final found = <String>[];
    void walk(Directory dir, int depth) {
      if (depth > 4) return;
      final List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final e in entries) {
        final name = p.basename(e.path);
        if (e is Directory) {
          if (!_skippedDirs.contains(name) && !name.startsWith('.')) {
            walk(e, depth + 1);
          }
        } else if (e is File &&
            name.startsWith('ExportOptions') &&
            name.endsWith('.plist')) {
          found.add(rel(e.path));
        }
      }
    }

    walk(Directory(root), 0);
    return found..sort();
  }

  String? _arbDirFromL10nYaml() {
    final l10n = _yaml('l10n.yaml');
    final dir = l10n?['arb-dir'];
    return dir is String ? p.split(p.normalize(dir)).join('/') : null;
  }

  static final _localeSuffix = RegExp(
    r'_([a-z]{2,3}(?:[_-](?:[A-Z][a-z]{3}|[A-Z]{2}|\d{3}))*)$',
  );

  void _loadArb() {
    final dir = Directory(abs(arbDir));
    if (!dir.existsSync()) return;
    final files = dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.arb'),
    );
    for (final file in files) {
      final relative = rel(file.path);
      String? locale;
      try {
        final json = jsonDecode(file.readAsStringSync());
        if (json is Map && json['@@locale'] is String) {
          locale = json['@@locale'] as String;
        }
      } on FormatException catch (e) {
        problems.add(FileProblem(relative, 'is not valid JSON: ${e.message}'));
        continue;
      }
      locale ??= _localeSuffix
          .firstMatch(p.basenameWithoutExtension(file.path))
          ?.group(1);
      if (locale != null) arbLocales[relative] = locale;
    }
  }
}
