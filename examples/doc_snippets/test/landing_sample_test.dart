/// The landing page's sample is the code in `lib/landing.dart`.
///
/// `site_fences_test.dart` holds every Markdown fence to its twin; the
/// landing page is a React page (`website/src/pages/index.tsx`) whose sample
/// is a template string, so it is read here instead: the string between
/// ``const sample = ` `` and the closing backtick must equal the region
/// between `// landing: start` and `// landing: end`, once both are dedented.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the landing page shows exactly the compiled sample', () {
    final Directory repo = _repoRoot();
    final String page =
        File('${repo.path}/website/src/pages/index.tsx').readAsStringSync();
    final String twin =
        File('${repo.path}/examples/doc_snippets/lib/landing.dart')
            .readAsStringSync();

    final RegExpMatch? shown =
        RegExp(r'const sample = `([^`]*)`').firstMatch(page);
    expect(shown, isNotNull,
        reason: 'index.tsx has no `const sample = `...`` template string');
    final String fence = shown!.group(1)!;
    expect(fence, isNot(contains(RegExp(r'(?<!\\)\$\{'))),
        reason: 'the sample must be literal text, not an interpolation');

    final List<String> lines = twin.split('\n');
    final int start =
        lines.indexWhere((String l) => l.trim() == '// landing: start');
    final int end =
        lines.indexWhere((String l) => l.trim() == '// landing: end');
    expect(start, isNonNegative, reason: 'landing.dart lost its start marker');
    expect(end, greaterThan(start), reason: 'landing.dart lost its end marker');

    // A bare `$error` is literal in a template string; an escaped `\$`, which
    // a `${…}` in a sample would need, is read back as the `$` it shows.
    final String got = _normalise(fence.replaceAll(r'\$', r'$').split('\n'));
    final String want = _normalise(lines.sublist(start + 1, end));
    expect(got, want,
        reason: 'website/src/pages/index.tsx has drifted from '
            'examples/doc_snippets/lib/landing.dart. The twin is what '
            'compiles; the page is what a reader copies.');
  });
}

String _normalise(List<String> lines) {
  final List<String> trimmed =
      lines.map((String l) => l.trimRight()).toList(growable: false);
  final Iterable<String> content = trimmed.where((String l) => l.isNotEmpty);
  final int indent = content.isEmpty
      ? 0
      : content
          .map((String l) => l.length - l.trimLeft().length)
          .reduce((int a, int b) => a < b ? a : b);
  return <String>[
    for (final String l in trimmed) l.isEmpty ? l : l.substring(indent),
  ].join('\n').trim();
}

Directory _repoRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 8; i++) {
    if (File('${dir.path}/website/src/pages/index.tsx').existsSync() &&
        File('${dir.path}/examples/doc_snippets/lib/landing.dart')
            .existsSync()) {
      return dir;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not find the repository root from ${Directory.current.path}.');
}
