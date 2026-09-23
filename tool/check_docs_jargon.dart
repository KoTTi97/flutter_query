// Fails when user-facing documentation carries the project's internal
// bookkeeping: review rounds, dates, finding and ticket IDs, the upstream pin.
//
//   dart run tool/check_docs_jargon.dart              # scan, exit 1 on a hit
//   dart run tool/check_docs_jargon.dart --self-test  # check the patterns
//
// What a user reads, and so what is scanned:
//
// * the site's pages, `website/docs/**/*.md` and `*.mdx`;
// * each package's `README.md`;
// * each package's `CHANGELOG.md`, its top entry only — older entries are
//   history and may say what they said;
// * every `///` line under `packages/*/lib`, which `dart doc` publishes;
// * the example apps' sources — `examples/showcase/lib`,
//   `examples/task_manager/lib` and `packages/query_kit_flutter/example/lib`
//   — which the site shows whole on its Examples pages: every `//` and `///`
//   comment and every string literal in them (a string is what the running
//   demo puts on screen).
//
// A line that must keep its reference says so with `<!-- jargon-ok -->`
// (Markdown), `{/* jargon-ok */}` (MDX, which has no HTML comments) or
// `// jargon-ok` (a doc comment) anywhere on it. A changelog's `## ` version
// headings are exempt: a release date there is what a changelog is for.
//
// The patterns are written to be blocking: each names a shape the project's
// bookkeeping uses and ordinary prose does not — an ordinal pass only in
// parentheses ("(second pass, …)"), not "on the second pass over the list";
// a finding ID only with its prefix. The self-test holds both sides.
import 'dart:io';

/// The patterns, each with the name a hit is reported under.
final List<(String, RegExp)> patterns = [
  (
    'review round',
    RegExp(
      r'\b(?:review rounds?|release review|'
      r'(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)'
      r' review)\b|'
      r'\((?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|'
      r'tenth) pass\b',
      caseSensitive: false,
    ),
  ),
  ('date', RegExp(r'2026-\d\d-\d\d')),
  ('finding C', RegExp(r'\bC\d{1,2}\b')),
  ('map', RegExp(r'\bmap #\d+', caseSensitive: false)),
  ('ADR', RegExp(r'\bADR-\d+')),
  ('issue link', RegExp(r'/issues/\d+')),
  ('issue number', RegExp(r'\(#\d+\b|\B#\d+\)')),
  ('upstream pin', RegExp(r'50680b98c')),
  (
    'finding ID',
    RegExp(r'\b(?:LIB|MU|AR|QE|BIND|REL|API|IN)-\d+\b|\bV-[BC]-\d+\b|'
        r'\b[LBRV]\d-\d+\b'),
  ),
];

/// The example sources the site shows whole: every comment and every string
/// in them is user-facing.
const shownSources = [
  'examples/showcase/lib',
  'examples/task_manager/lib',
  'packages/query_kit_flutter/example/lib',
];

/// The markers that let one line keep a reference.
const optOuts = ['<!-- jargon-ok -->', '{/* jargon-ok */}', '// jargon-ok'];

/// The names of the patterns [line] hits; empty when it is clean or opted out.
List<String> hitsIn(String line) {
  if (optOuts.any(line.contains)) return const [];
  return [
    for (final (name, pattern) in patterns)
      if (pattern.hasMatch(line)) name,
  ];
}

/// A string literal on one line: single- or double-quoted, raw or not.
final RegExp _stringLiteral =
    RegExp(r'''r?'(?:[^'\\]|\\.)*'|r?"(?:[^"\\]|\\.)*"''');

/// What a reader sees of one line of Dart source: the contents of its string
/// literals and its comment (`//`, `///`, or a `/*` on the line), joined; the
/// code around them is dropped, so an identifier never counts. The opt-out
/// marker is a comment and so is kept, and [hitsIn] still honours it.
String userTextOf(String line) {
  final parts = <String>[];
  final code = line.replaceAllMapped(_stringLiteral, (m) {
    parts.add(m[0]!);
    return '';
  });
  final comment = code.indexOf(RegExp(r'//|/\*'));
  if (comment >= 0) parts.add(code.substring(comment));
  return parts.join(' ');
}

/// The top entry of a changelog: from its first `## ` heading up to the
/// second, as `(first line number, lines)`.
(int, List<String>) topEntry(List<String> lines) {
  final start = lines.indexWhere((l) => l.startsWith('## '));
  if (start < 0) return (1, lines);
  final next = lines.indexWhere((l) => l.startsWith('## '), start + 1);
  return (start + 1, lines.sublist(start, next < 0 ? lines.length : next));
}

void main(List<String> args) {
  if (args.contains('--self-test')) {
    exit(_selfTest());
  }
  final root = File.fromUri(Platform.script).parent.parent;
  final hits = <String>[];

  void scan(
    File file, {
    bool docCommentsOnly = false,
    bool topOnly = false,
    bool shownSource = false,
  }) {
    var lines = file.readAsLinesSync();
    var first = 1;
    if (topOnly) (first, lines) = topEntry(lines);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (docCommentsOnly && !line.trimLeft().startsWith('///')) continue;
      if (topOnly && line.startsWith('## ')) continue;
      final names = hitsIn(shownSource ? userTextOf(line) : line);
      if (names.isEmpty) continue;
      final path = file.path.substring(root.path.length + 1);
      hits.add('$path:${first + i}: [${names.join(', ')}] ${line.trim()}');
    }
  }

  Iterable<File> filesUnder(String dir, bool Function(String) wanted) {
    final directory = Directory('${root.path}/$dir');
    if (!directory.existsSync()) return const [];
    return directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => wanted(f.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  for (final file in filesUnder(
    'website/docs',
    (p) => p.endsWith('.md') || p.endsWith('.mdx'),
  )) {
    scan(file);
  }
  final packages = Directory('${root.path}/packages')
      .listSync()
      .whereType<Directory>()
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final package in packages) {
    final readme = File('${package.path}/README.md');
    if (readme.existsSync()) scan(readme);
    final changelog = File('${package.path}/CHANGELOG.md');
    if (changelog.existsSync()) scan(changelog, topOnly: true);
    final name = package.path.substring(root.path.length + 1);
    for (final file in filesUnder('$name/lib', (p) => p.endsWith('.dart'))) {
      scan(file, docCommentsOnly: true);
    }
  }

  for (final dir in shownSources) {
    for (final file in filesUnder(dir, (p) => p.endsWith('.dart'))) {
      scan(file, shownSource: true);
    }
  }

  if (hits.isEmpty) {
    stdout.writeln('No internal jargon in the user-facing docs.');
    return;
  }
  hits.forEach(stdout.writeln);
  stderr.writeln(
    '\n${hits.length} line(s) carry internal references. Reword them, or '
    'mark a line that must keep one with <!-- jargon-ok -->, '
    '{/* jargon-ok */} (MDX) or // jargon-ok.',
  );
  exit(1);
}

/// Checks [hitsIn] and [topEntry] against known lines; returns the exit code.
int _selfTest() {
  const flagged = {
    'found by the ninth review': 'review round',
    'the release review said so': 'review round',
    'fixed (second pass, V-B-3)': 'review round',
    'since 2026-09-12': 'date',
    'see C17 for why': 'finding C',
    'worked off by map #49': 'map',
    'as ADR-0002 decides': 'ADR',
    'github.com/KoTTi97/query_kit/issues/58': 'issue link',
    'upstream at 50680b98c': 'upstream pin',
    'LIB-3 covers it': 'finding ID',
    'MU-2, AR-1 and QE-4': 'finding ID',
    'V-B-3 held': 'finding ID',
    '(V5-1)': 'finding ID',
    'release review, 2026-09-23, L3-2': 'finding ID',
    '(API-02)': 'finding ID',
    'IN-02 said so': 'finding ID',
    'the documented limit (AR-01, R3-1)': 'finding ID',
    '(fourth pass,': 'review round',
    'a pre-release review said': 'review round',
    'it came home (#69).': 'issue number',
    'the suites already read (C56, #51).': 'issue number',
  };
  const clean = [
    'Call refetch to fetch again.',
    'a C major chord, ABC12, C1000',
    'the second page, a passing test',
    'a map of the keys #1',
    'ADR without a number',
    '2025-01-01 is not this project',
    'see the issues page',
    'LIBRARY-3 and V-3',
    'since 2026-09-12 <!-- jargon-ok -->',
    'since 2026-09-12 {/* jargon-ok */}',
    '/// C17 // jargon-ok',
    'on the first pass over the list, and a second pass after it',
    'review the release notes before a release; review your options',
    'a Uint8List of length L1, the B-tree, R2-D2',
    'Take a second look at the review.',
    "title: 'Post #1',",
    'Comments on post #1',
  ];
  // What a shown source contributes: its strings and its comment, never its
  // code.
  const sourceLines = {
    "  note: 'fixed since C49',": ['finding C'],
    '  final c = C49(); // see ADR-0001': ['ADR'],
    "  final url = 'https://example.com/issues/7';": ['issue link'],
    '  final C12 = map[#3];': <String>[],
    "  final s = 'since 2026-09-12'; // jargon-ok": <String>[],
    "  text: 'a // b', // (#69)": ['issue number'],
    '/// Found by the ninth review.': ['review round'],
    r"  label: 'it\'s C7', /* C8 */": ['finding C'],
  };
  final failures = <String>[];
  sourceLines.forEach((line, expected) {
    final got = hitsIn(userTextOf(line));
    if (got.length != expected.length || !got.every(expected.contains)) {
      failures.add('expected $expected in source line: $line (got $got)');
    }
  });
  flagged.forEach((line, name) {
    if (!hitsIn(line).contains(name)) {
      failures.add('expected [$name] in: $line (got ${hitsIn(line)})');
    }
  });
  for (final line in clean) {
    if (hitsIn(line).isNotEmpty) {
      failures.add('expected no hit in: $line (got ${hitsIn(line)})');
    }
  }
  final (first, entry) = topEntry([
    '# Changelog',
    '',
    '## 1.0.0',
    '- new',
    '## 0.1.0',
    '- 2026-09-01 old',
  ]);
  if (first != 3 || entry.length != 2 || entry.last != '- new') {
    failures.add('topEntry kept the wrong lines: $first $entry');
  }
  if (failures.isEmpty) {
    stdout.writeln(
      'check_docs_jargon self-test: '
      '${flagged.length + clean.length + sourceLines.length + 1} '
      'cases pass.',
    );
    return 0;
  }
  failures.forEach(stderr.writeln);
  return 1;
}
