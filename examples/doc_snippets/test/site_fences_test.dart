/// The check behind the site's central documentation claim.
///
/// `website/README.md` says: *"Every Dart sample appears in
/// `examples/doc_snippets/`, compiled and analyzed at `--fatal-infos` in CI,
/// under a comment naming the page it is on. **A sample and its twin are kept
/// identical; that is the only reason to trust either.**"*
///
/// Nothing checked the second sentence. The twins compiled, so a sample could
/// not name a method that no longer existed — but a fence could drift from
/// its twin by a renamed parameter, a dropped line or a whole rewritten body
/// and both halves would still be green. Fifty fences, none verified
/// (map #70, https://github.com/KoTTi97/flutter_query/issues/72).
///
/// So a region of a twin file is marked, and the fence that shows it names
/// the region:
///
/// ```dart
/// // >>> guides/rebuilds.md#select-counts
/// select: (tasks) => tasks.where((s) => s.done).length,
/// // <<<
/// ```
///
///     ```dart snippet="guides/rebuilds.md#select-counts"
///
/// A fence that shows two declarations together names both, in the order it
/// shows them, and they are compared with one blank line between — because a
/// page often introduces a key and the options that use it as one block while
/// the twin keeps each where Dart wants it:
///
///     ```dart snippet="getting-started/first-query.md#key first-query.md#options"
///
/// The id rides on the fence's **metastring** rather than on an adjacent HTML
/// comment, because an editor can move a comment away from its fence and
/// cannot move an attribute off it. Docusaurus passes unknown metastring keys
/// through untouched, so it is inert for rendering.
///
/// Writing this check found that the README's claim was **aspirational**: a
/// good third of the fences were never identical to their twin and should not
/// be. A page that introduces `QueryBuilder` shows
/// `builder: (context, result) => switch (result) { /* … */ }` on purpose —
/// four lines about one thing — and spelling the switch out to satisfy a
/// checker would make the page worse. So a fence declares which of three
/// things it is:
///
/// * `snippet="<id>"` — an **exact** twin, character for character. The
///   strong guarantee, and the default: a reader can copy it.
/// * `snippet="excerpt: <id>"` — the page **elides**. The id must still
///   resolve, so the sample is anchored to code that compiles and a deleted
///   twin is caught; the lines are not compared, and the fence must carry a
///   visible `…` so the reader knows something was left out. That last part
///   is what stops `excerpt:` becoming a way to silence a real drift.
/// * `snippet="prose-only: <reason>"` — **no twin**, because the sample needs
///   a third-party package (`dio`, `connectivity_plus`, `signals_flutter`)
///   and neither published package may depend on one (map #1). That exception
///   was remembered; now it is declared, with a reason, and auditable.
///
/// What every tier buys, including the weakest: when the API moves, the twin
/// stops compiling, and whoever fixes it is looking at a marker naming the
/// page that shows it.
///
/// This test lives in `examples/doc_snippets/test/` and not in `tool/` for
/// two reasons: it runs inside the existing `doc snippet tests` step in both
/// the `gates` and `floors` jobs, so CI needs no new step; and it is a test
/// of the module whose whole purpose is the site's samples, so the
/// per-commit gate already routes an editor of either side into it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final Directory repo = _repoRoot();
  final List<_Fence> fences = _fencesOf(Directory('${repo.path}/website/docs'));
  final Map<String, _Region> regions = _regionsOf(repo);

  // A guard on the guard: if the glob or the root ever stops resolving, every
  // other case in this file passes vacuously and says nothing.
  test('the site and the twins are both where this test expects them', () {
    expect(fences, isNotEmpty,
        reason: 'no dart fences found under website/docs — wrong repo root?');
    expect(regions, isNotEmpty,
        reason: 'no snippet regions found in the twin files');
  });

  test(
      'every dart fence on the site names a snippet region, or says why it '
      'has none', () {
    final List<String> unnamed = <String>[
      for (final _Fence f in fences)
        if (f.regionIds.isEmpty && f.proseOnlyReason == null) f.where,
    ];
    expect(
      unnamed,
      isEmpty,
      reason: 'These dart fences carry no `snippet=`. Add a twin in '
          'examples/doc_snippets/ and name it, or — only if the sample needs '
          'a third-party package — declare '
          'snippet="prose-only: <reason>":\n  ${unnamed.join('\n  ')}',
    );

    // A declared exception is still an exception: it has to give a reason,
    // and the reason is what a reader of the ticket audits.
    for (final _Fence f in fences) {
      if (f.proseOnlyReason != null) {
        expect(
          f.proseOnlyReason!.trim(),
          isNotEmpty,
          reason: '${f.where}: prose-only needs a reason after the colon',
        );
      }
    }
  });

  test('every fence matches its region, character for character', () {
    for (final _Fence f in fences) {
      if (f.regionIds.isEmpty || f.isExcerpt) continue;
      if (f.regionIds.any((String id) => !regions.containsKey(id))) {
        continue; // reported by the resolution case below.
      }
      final List<_Region> parts =
          f.regionIds.map((String id) => regions[id]!).toList();

      // Several regions read as one sample with a blank line between them,
      // which is how the page shows them.
      final List<String> want = <String>[];
      for (final _Region part in parts) {
        if (want.isNotEmpty) want.add('');
        want.addAll(_normalise(part.lines));
      }

      final List<String> got = _normalise(f.lines);
      if (_same(want, got)) continue;

      final int at = _firstDifference(want, got);
      final String from = parts.map((_Region r) => r.where).join(' + ');
      fail(
        '${f.where} has drifted from $from.\n'
        'First difference at line ${at + 1} of the sample:\n'
        '  twin:  ${at < want.length ? want[at] : '(nothing — twin is shorter)'}\n'
        '  fence: ${at < got.length ? got[at] : '(nothing — fence is shorter)'}\n'
        '\n--- the twin (${want.length} lines) ---\n${want.join('\n')}\n'
        '\n--- the fence (${got.length} lines) ---\n${got.join('\n')}\n'
        '\nOne of the two is wrong. Neither is authoritative: the twin is what '
        'compiles, the fence is what a reader copies.',
      );
    }
  });

  test('every region is on the page it names, exactly once', () {
    final Map<String, List<_Fence>> byId = <String, List<_Fence>>{};
    for (final _Fence f in fences) {
      for (final String id in f.regionIds) {
        (byId[id] ??= <_Fence>[]).add(f);
      }
    }

    // An orphan is a twin for a sample somebody deleted. It still compiles,
    // so nothing else would ever notice.
    final List<String> orphans = <String>[
      for (final _Region r in regions.values)
        if (!byId.containsKey(r.id)) '${r.id} (${r.where})',
    ];
    expect(orphans, isEmpty,
        reason: 'These regions are marked in a twin and shown on no page. '
            'Delete the markers, or add the fence:\n  ${orphans.join('\n  ')}');

    // The same sample may appear on two pages — `rebuilds.md` and
    // `mutations.md` both show the mutation `buildWhen`, and duplicating it
    // in the twin so each page could own a copy would be the drift this file
    // exists to prevent. Twice on *one* page is still a mistake.
    final List<String> twice = <String>[
      for (final MapEntry<String, List<_Fence>> e in byId.entries)
        for (final String page in e.value
            .map((_Fence f) => f.page)
            .toSet()
            .where((String page) =>
                e.value.where((_Fence f) => f.page == page).length > 1))
          '${e.key} appears twice on $page',
    ];
    expect(twice, isEmpty,
        reason: 'One region, two fences on one page. Give the second its own '
            'region:\n  ${twice.join('\n  ')}');

    // An id is `<page>#<slug>`, naming the page the sample *belongs* to — so
    // a reader of the twin knows where to look, and a fence that borrows
    // another page's sample says whose it is. The page part has to be a real
    // page, or a typo there would make the id merely decorative.
    final Set<String> pages = fences.map((_Fence f) => f.page).toSet();
    final List<String> unknown = <String>[
      for (final _Fence f in fences)
        for (final String id in f.regionIds)
          if (!id.contains('#'))
            '${f.where} names $id — ids are "<page>#<slug>"'
          else if (!pages.contains(id.split('#').first))
            '${f.where} names $id, whose page part is not a page that has '
                'dart fences',
    ];
    expect(unknown, isEmpty, reason: unknown.join('\n  '));
  });

  test('every excerpt says so, with an ellipsis a reader can see', () {
    // Without this, `excerpt:` is a way to silence a drift: mark the fence an
    // excerpt and the line comparison stops running. An excerpt has to *look*
    // elided, on the page, to the reader.
    final List<String> silent = <String>[
      for (final _Fence f in fences)
        if (f.isExcerpt && !f.lines.any((String l) => l.contains('…')))
          '${f.where} is marked an excerpt and elides nothing visible — '
              'either drop the "excerpt: " prefix and make it match, or show '
              'the … it leaves out',
    ];
    expect(silent, isEmpty, reason: silent.join('\n  '));
  });

  test('every region id is unique and every fence id resolves', () {
    final List<String> unresolved = <String>[
      for (final _Fence f in fences)
        for (final String id in f.regionIds)
          if (!regions.containsKey(id))
            '${f.where} names $id, which no twin marks',
    ];
    expect(unresolved, isEmpty,
        reason: 'A typo here would otherwise skip the comparison '
            'silently:\n  ${unresolved.join('\n  ')}');

    // Duplicate marker ids cannot be represented in `regions` (the later one
    // would win), so they are counted while parsing and asserted here.
    expect(_duplicateRegionIds, isEmpty,
        reason: 'The same region id is marked twice in the twins:\n  '
            '${_duplicateRegionIds.join('\n  ')}');
  });
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

/// What "identical" means: the same lines, once the block's own indentation
/// and trailing whitespace are out of the way.
///
/// Dedenting is what lets a marker sit *inside* a method body while the fence
/// shows the sample flush left — which is the difference between a twin that
/// has to be shaped like the page and one that can be shaped like Dart.
/// Nothing else is forgiven: a renamed parameter, a dropped line and a
/// reflowed comment are all differences, because a reader copies the fence.
List<String> _normalise(List<String> lines) {
  final List<String> trimmed =
      lines.map((String l) => l.trimRight()).toList(growable: false);
  final Iterable<String> content = trimmed.where((String l) => l.isNotEmpty);
  final int indent = content.isEmpty
      ? 0
      : content
          .map((String l) => l.length - l.trimLeft().length)
          .reduce((int a, int b) => a < b ? a : b);
  final List<String> dedented = <String>[
    for (final String l in trimmed) l.isEmpty ? l : l.substring(indent),
  ];
  int start = 0;
  int end = dedented.length;
  while (start < end && dedented[start].isEmpty) {
    start++;
  }
  while (end > start && dedented[end - 1].isEmpty) {
    end--;
  }
  return dedented.sublist(start, end);
}

/// Identical, with one narrow allowance: the twin's last line may carry a
/// trailing `;` or `,` the page does not.
///
/// A twin is Dart, so a sample is a *statement* there — `QueryBuilder<Task>(…);`
/// as an arrow body, or `QueryClientProvider(…),` as an argument. A page shows
/// the same sample as the *expression* a reader drops into their own code.
/// Forcing the two to agree would mean either printing a stray semicolon on
/// every page or wrapping every page's sample in a declaration it does not
/// need. The allowance cannot hide a drift: it is exactly one character, at
/// the very end, and only the one that separates a statement from an
/// expression.
bool _same(List<String> want, List<String> got) {
  if (want.join('\n') == got.join('\n')) return true;
  if (want.isEmpty || got.isEmpty) return false;
  final String last = want.last;
  if (last.endsWith(';') || last.endsWith(',')) {
    final List<String> withoutSeparator = <String>[
      ...want.sublist(0, want.length - 1),
      last.substring(0, last.length - 1),
    ];
    return withoutSeparator.join('\n') == got.join('\n');
  }
  return false;
}

int _firstDifference(List<String> a, List<String> b) {
  final int shorter = a.length < b.length ? a.length : b.length;
  for (int i = 0; i < shorter; i++) {
    if (a[i] != b[i]) return i;
  }
  return shorter;
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// A ```dart fence on a documentation page.
class _Fence {
  _Fence({
    required this.page,
    required this.line,
    required this.lines,
    required this.regionIds,
    required this.isExcerpt,
    required this.proseOnlyReason,
  });

  /// The page's path under `website/docs`, e.g. `guides/rebuilds.md`.
  final String page;
  final int line;
  final List<String> lines;

  /// The regions this fence shows, in the order it shows them. Empty when the
  /// fence declared itself prose-only.
  final List<String> regionIds;

  /// Whether the page elides part of the sample, and is therefore compared
  /// by resolution rather than line by line.
  final bool isExcerpt;
  final String? proseOnlyReason;

  String get where => '$page:$line';
}

/// A marked region of a twin file.
class _Region {
  _Region({required this.id, required this.where, required this.lines});

  final String id;
  final String where;
  final List<String> lines;
}

final List<String> _duplicateRegionIds = <String>[];

final RegExp _snippetAttribute = RegExp(r'snippet="([^"]*)"');

List<_Fence> _fencesOf(Directory docs) {
  final List<_Fence> fences = <_Fence>[];
  final List<File> pages = docs
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.md'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  for (final File page in pages) {
    final String rel = page.path
        .substring(docs.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    final List<String> lines = page.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith('```dart')) continue;
      final String meta = lines[i].substring('```dart'.length);
      int j = i + 1;
      while (j < lines.length && !lines[j].startsWith('```')) {
        j++;
      }
      final String? attribute = _snippetAttribute.firstMatch(meta)?.group(1);
      final bool proseOnly = attribute?.startsWith('prose-only:') ?? false;
      final bool excerpt = attribute?.startsWith('excerpt:') ?? false;
      final String? value =
          excerpt ? attribute!.substring('excerpt:'.length) : attribute;
      final String? reason =
          proseOnly ? attribute!.substring('prose-only:'.length) : null;
      fences.add(_Fence(
        page: rel,
        line: i + 1,
        lines: lines.sublist(i + 1, j),
        regionIds: proseOnly || value == null
            ? const <String>[]
            : value
                .split(RegExp(r'\s+'))
                .where((String s) => s.isNotEmpty)
                .toList(),
        isExcerpt: excerpt,
        proseOnlyReason: reason,
      ));
      i = j;
    }
  }
  return fences;
}

/// Every Dart file of this package is a candidate twin — `lib/` for the
/// samples the analyzer proves compile, `test/` for the ones that have to
/// *run* (the testing guide's teardown, ADR-0002). Discovered rather than
/// listed, so adding a twin file is adding a file.
Map<String, _Region> _regionsOf(Directory repo) {
  final Directory pkg = Directory('${repo.path}/examples/doc_snippets');
  final List<File> twins = <File>[
    for (final String sub in <String>['lib', 'test'])
      if (Directory('${pkg.path}/$sub').existsSync())
        ...Directory('${pkg.path}/$sub')
            .listSync(recursive: true)
            .whereType<File>()
            .where((File f) => f.path.endsWith('.dart')),
  ]..sort((File a, File b) => a.path.compareTo(b.path));

  final Map<String, _Region> regions = <String, _Region>{};
  _duplicateRegionIds.clear();

  for (final File file in twins) {
    final String twin = file.path
        .substring(repo.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    final List<String> lines = file.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final String open = lines[i].trim();
      if (!open.startsWith('// >>> ')) continue;
      final String id = open.substring('// >>> '.length).trim();
      int j = i + 1;
      while (j < lines.length && lines[j].trim() != '// <<<') {
        j++;
      }
      if (j == lines.length) {
        fail('$twin:${i + 1} opens region "$id" and never closes it '
            '(expected a `// <<<` line).');
      }
      final _Region region = _Region(
        id: id,
        where: '$twin:${i + 1}',
        lines: lines.sublist(i + 1, j),
      );
      if (regions.containsKey(id)) {
        _duplicateRegionIds
            .add('$id (${regions[id]!.where} and ${region.where})');
      }
      regions[id] = region;
      i = j;
    }
  }
  return regions;
}

/// Walks up from the test's own directory until the workspace root is in
/// sight, so the test does not care where `flutter test` was invoked from.
Directory _repoRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 8; i++) {
    if (Directory('${dir.path}/website/docs').existsSync() &&
        File('${dir.path}/examples/doc_snippets/lib/doc_snippets.dart')
            .existsSync()) {
      return dir;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not find the repository root from ${Directory.current.path}. '
      'This test reads website/docs and examples/doc_snippets.');
}
