// Renames the two published packages — directories, pubspec names, every
// import and every mention in prose — in one pass.
//
// The name a package is published under is permanent (pub.dev never frees a
// name), so the decision was deliberately left until last rather than made
// first. This script is what made that safe, and it is what produced the
// settled names — `query_kit` and `query_kit_flutter`, decided 2026-09-10.
// It stays because the path it takes is the only supported way to move a
// name, and because keeping it exercised is what makes the names cheap to
// move if pub.dev ever forces the question.
//
//   dart run tool/rename_packages.dart --core query_kit --flutter query_kit_flutter
//
// Add --dry-run to see the plan without touching anything. After a real run,
// the whole gate has to pass — `docs/releasing.md` says which commands.
import 'dart:convert';
import 'dart:io';

/// Files whose mentions of a package name are a record of something that was
/// true when it was written, not a reference to this package.
const _frozen = <String>{
  'docs/research/package-naming-and-affiliation.md',
};

void main(List<String> args) {
  final options = _parse(args);

  final current = _currentNames();
  final renames = <String, String>{
    if (current.core != options.core) current.core: options.core,
    if (current.flutter != options.flutter) current.flutter: options.flutter,
    if (current.workspace != '_${options.core}_workspace')
      current.workspace: '_${options.core}_workspace',
  };
  if (renames.isEmpty) {
    stdout.writeln('Nothing to do: the packages are already named that.');
    return;
  }
  for (final entry in renames.entries) {
    stdout.writeln('${entry.key} -> ${entry.value}');
  }

  // Longest first, so a name that is a prefix of another is never applied to
  // it first and left half-rewritten.
  final ordered = renames.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  final tracked = _run('git', ['ls-files', '-z']).split(String.fromCharCode(0))
    ..removeWhere((path) => path.isEmpty);

  var changed = 0;
  for (final path in tracked) {
    if (_frozen.contains(path)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    if (bytes.contains(0)) continue; // binary
    final before = utf8.decode(bytes);
    var after = before;
    for (final old in ordered) {
      after = after.replaceAll(old, renames[old]!);
    }
    if (after == before) continue;
    changed++;
    if (!options.dryRun) file.writeAsStringSync(after);
  }
  stdout.writeln('$changed file${changed == 1 ? '' : 's'} rewritten.');

  // Paths carry the name too: the package directories, and the library
  // entrypoint inside each one. Deepest first, so a file is moved before the
  // directory it sits in.
  final moves = <String, String>{};
  for (final path in tracked) {
    var renamed = path;
    for (final old in ordered) {
      renamed = renamed.replaceAll(old, renames[old]!);
    }
    if (renamed != path) moves[path] = renamed;
  }
  for (final from in moves.keys.toList()
    ..sort((a, b) => b.split('/').length.compareTo(a.split('/').length))) {
    stdout.writeln('git mv $from ${moves[from]}');
    if (options.dryRun) continue;
    Directory(moves[from]!.substring(0, moves[from]!.lastIndexOf('/')))
        .createSync(recursive: true);
    _run('git', ['mv', from, moves[from]!]);
  }

  if (options.dryRun) return;

  // Generated package config names the old paths; leaving it behind makes the
  // first `dart test` after a rename fail in a way that looks like a code
  // error. The lockfile is rewritten by `pub get`, so it is left alone.
  for (final stale in Directory('.')
      .listSync(recursive: true, followLinks: false)
      .whereType<Directory>()
      .where((directory) => directory.path.endsWith('/.dart_tool'))
      .toList()
      .reversed) {
    if (stale.existsSync()) stale.deleteSync(recursive: true);
  }
  stdout
    ..writeln('')
    ..writeln('Done. Next: `flutter pub get` (which rewrites pubspec.lock), '
        'then the gate in docs/releasing.md.');
}

class _Options {
  _Options(this.core, this.flutter, this.dryRun);

  final String core;
  final String flutter;
  final bool dryRun;
}

_Options _parse(List<String> args) {
  String? core;
  String? flutter;
  var dryRun = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--core':
        core = args[++i];
      case '--flutter':
        flutter = args[++i];
      case '--dry-run':
        dryRun = true;
      default:
        _fail('unknown argument "${args[i]}"');
    }
  }
  final coreName = core, flutterName = flutter;
  if (coreName == null || flutterName == null) {
    _fail('both --core and --flutter are required');
  }
  for (final name in <String>[coreName, flutterName]) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      _fail('"$name" is not a valid pub package name ([a-z0-9_], no leading '
          'digit)');
    }
  }
  if (!flutterName.endsWith('_flutter')) {
    // `_currentNames` tells the two apart by this suffix, so the next rename
    // would not find them.
    _fail('the binding\'s name has to end in `_flutter`');
  }
  return _Options(coreName, flutterName, dryRun);
}

class _Names {
  _Names(this.core, this.flutter, this.workspace);

  final String core;
  final String flutter;
  final String workspace;
}

/// The names in play right now, read from the workspace root rather than
/// hard-coded, so this script survives its own renames.
_Names _currentNames() {
  final pubspec = File('pubspec.yaml').readAsLinesSync();
  final workspace = pubspec
      .firstWhere((line) => line.startsWith('name:'))
      .split(':')
      .last
      .trim();
  final packages = <String>[
    for (final line in pubspec)
      if (RegExp(r'^\s*-\s*packages/[a-z0-9_]+\s*$').hasMatch(line))
        line.split('/').last.trim(),
  ];
  if (packages.length != 2) {
    _fail('expected exactly two `packages/…` entries in the root pubspec, '
        'found ${packages.length}');
  }
  final flutter = packages.firstWhere(
    (name) => name.endsWith('_flutter'),
    orElse: () => _fail('neither package directory ends in `_flutter`'),
  );
  return _Names(
      packages.firstWhere((name) => name != flutter), flutter, workspace);
}

Never _fail(String message) {
  stderr.writeln('rename_packages: $message');
  exit(2);
}

String _run(String executable, List<String> arguments) {
  final result = Process.runSync(executable, arguments);
  if (result.exitCode != 0) {
    _fail('$executable ${arguments.join(' ')} failed:\n${result.stderr}');
  }
  return result.stdout as String;
}
