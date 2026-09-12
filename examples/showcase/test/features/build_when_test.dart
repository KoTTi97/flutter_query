/// The `build-when` screen against the fake backend.
///
/// Every number here is a build count, and the screen's header says why each
/// one is what it is. Two things the fake needs before it can show any of
/// them: a latency, because a notification that arrives in the same frame as
/// the one before it is **one** rebuild and the point of the screen is that
/// the flip and the landing are two; and the tall window below, because a
/// lazily built list would not hold sixteen readers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// Five cards and two strips, sixteen readers between them.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 5200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Long enough that the flip to fetching and the landing are separate
/// frames, short enough that a test steps over it in one `pump`.
const Duration slow = Duration(milliseconds: 200);

const List<String> queryMembers = <String>[
  'watchQuery',
  'context.query',
  'watchSelectQuery',
  'context.selectQuery',
];

const List<String> infiniteMembers = <String>[
  'watchInfiniteQuery',
  'context.infiniteQuery',
];

const List<String> mutationMembers = <String>[
  'watchMutation',
  'context.mutation',
];

/// One reader's group: `reader watchQuery filtered`, the way a strip is
/// `debug posts`.
String readerName(String member, {required bool filtered}) =>
    'reader $member ${filtered ? 'filtered' : 'plain'}';

Finder readerFact(String member,
        {required bool filtered, required String text}) =>
    factIn(readerName(member, filtered: filtered), text);

/// Both halves of every pair in [members], by their build counts.
void expectBuilds(
  List<String> members, {
  required int filtered,
  required int plain,
}) {
  for (final member in members) {
    expect(
      readerFact(member, filtered: true, text: 'builds=$filtered'),
      findsOneWidget,
      reason: '$member filtered',
    );
    expect(
      readerFact(member, filtered: false, text: 'builds=$plain'),
      findsOneWidget,
      reason: '$member plain',
    );
  }
}

/// Taps one segment of the knob named `predicate`.
Future<void> chooseFilter(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: groupNamed('predicate'), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  showcaseTest('sixteen readers, one request per entry', (tester, h) async {
    tall(tester);
    await h.open(tester, '/build-when');

    expect(h.requests('GET', '/api/posts'), 1);
    expect(h.requests('GET', RegExp(r'^/api/projects')), 1);
    expect(h.fact('posts', 'fetches=1'), findsOneWidget);
    expect(h.fact('posts', 'observers=8'), findsOneWidget);
    expect(h.fact('pages', 'fetches=1'), findsOneWidget);
    expect(h.fact('pages', 'observers=4'), findsOneWidget);

    // Every member of the eight is on screen twice, and shows what it read.
    for (final filtered in <bool>[true, false]) {
      for (final member in <String>['watchQuery', 'context.query']) {
        expect(readerFact(member, filtered: filtered, text: 'posts=30'),
            findsOneWidget);
      }
      for (final member in <String>[
        'watchSelectQuery',
        'context.selectQuery',
      ]) {
        expect(readerFact(member, filtered: filtered, text: 'count=30'),
            findsOneWidget);
      }
      for (final member in infiniteMembers) {
        expect(readerFact(member, filtered: filtered, text: 'pages=1'),
            findsOneWidget);
      }
      for (final member in mutationMembers) {
        expect(readerFact(member, filtered: filtered, text: 'status=idle'),
            findsOneWidget);
      }
    }

    // Pending, then the data — a change of the data, so the predicate lets
    // the second one through as well. A mutation has reported nothing yet.
    expectBuilds(queryMembers, filtered: 2, plain: 2);
    expectBuilds(infiniteMembers, filtered: 2, plain: 2);
    expectBuilds(mutationMembers, filtered: 1, plain: 1);
  });

  showcaseTest('a refetch with equal data moves only the plain half',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/build-when');
    h.backend.latency = slow;

    await tester.tap(find.byTooltip('Refetch the posts'));
    await tester.pump();

    // The flip to fetching: a changed result with unchanged data.
    expect(h.fact('posts', 'fetchStatus=fetching'), findsOneWidget);
    expectBuilds(queryMembers, filtered: 2, plain: 3);

    await tester.pump(slow);
    await tester.pumpAndSettle();

    expect(h.requests('GET', '/api/posts'), 2);
    expect(h.fact('posts', 'fetches=2'), findsOneWidget);
    // The landing — idle again, with a newer `dataUpdatedAt` — is the second
    // rebuild for the plain half; the filtered half refused both.
    expectBuilds(queryMembers, filtered: 2, plain: 4);
    // Nothing reached the other two entries.
    expectBuilds(infiniteMembers, filtered: 2, plain: 2);
    expectBuilds(mutationMembers, filtered: 1, plain: 1);
  });

  showcaseTest('dropping a post reaches every reader of the entry',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/build-when');

    await tester.tap(find.byTooltip('Drop a post'));
    await tester.pumpAndSettle();

    // A write, not a fetch: the data moved, so the predicate says yes.
    expect(h.requests('GET', '/api/posts'), 1);
    for (final filtered in <bool>[true, false]) {
      expect(readerFact('watchQuery', filtered: filtered, text: 'posts=29'),
          findsOneWidget);
      expect(
          readerFact('context.selectQuery',
              filtered: filtered, text: 'count=29'),
          findsOneWidget);
    }
    expectBuilds(queryMembers, filtered: 3, plain: 3);
  });

  showcaseTest('Load next is one build filtered and two plain',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/build-when');
    h.backend.latency = slow;

    await tester.tap(find.byTooltip('Load next'));
    await tester.pump();

    // The page fetch starting moves `fetchStatus` while the pages are still
    // the pages on screen, so the filtered half refuses it.
    expect(h.fact('pages', 'fetchStatus=fetching'), findsOneWidget);
    expectBuilds(infiniteMembers, filtered: 2, plain: 3);

    await tester.pump(slow);
    await tester.pumpAndSettle();

    expect(h.requests('GET', RegExp(r'^/api/projects')), 2);
    for (final member in infiniteMembers) {
      for (final filtered in <bool>[true, false]) {
        expect(readerFact(member, filtered: filtered, text: 'pages=2'),
            findsOneWidget);
      }
    }
    expectBuilds(infiniteMembers, filtered: 3, plain: 4);
    // One reader pages; the other three joined the same fetch.
    expect(h.fact('pages', 'observers=4'), findsOneWidget);
  });

  showcaseTest('a mutation run is two builds filtered and three plain',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/build-when');
    h.backend.latency = slow;

    await tester.tap(find.byTooltip('Run the mutation'));
    await tester.pump();

    // `idle` to `pending` carries no data, which is the one a mutation
    // reader can filter — it has no `select` to filter with.
    for (final member in mutationMembers) {
      expect(readerFact(member, filtered: true, text: 'status=idle'),
          findsOneWidget);
      expect(readerFact(member, filtered: false, text: 'status=pending'),
          findsOneWidget);
    }
    expectBuilds(mutationMembers, filtered: 1, plain: 2);

    await tester.pump(slow);
    await tester.pumpAndSettle();

    // Four readers, four mutations: one is never shared.
    expect(h.requests('POST', '/api/counter/increment'), 4);
    for (final member in mutationMembers) {
      for (final filtered in <bool>[true, false]) {
        expect(readerFact(member, filtered: filtered, text: 'status=success'),
            findsOneWidget);
      }
    }
    expectBuilds(mutationMembers, filtered: 2, plain: 3);
  });

  showcaseTest('never freezes the filtered half, always makes it its twin',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/build-when');

    // The knob is a rebuild from above, which no predicate can refuse.
    await chooseFilter(tester, 'never');
    expectBuilds(queryMembers, filtered: 3, plain: 3);

    h.backend.latency = slow;
    await tester.tap(find.byTooltip('Refetch the posts'));
    await tester.pump();
    await tester.pump(slow);
    await tester.pumpAndSettle();
    expect(h.fact('posts', 'fetches=2'), findsOneWidget);
    expectBuilds(queryMembers, filtered: 3, plain: 5);

    // `always` is no filter at all: from here the pair moves together.
    await chooseFilter(tester, 'always');
    expectBuilds(queryMembers, filtered: 4, plain: 6);
    await tester.tap(find.byTooltip('Refetch the posts'));
    await tester.pump();
    await tester.pump(slow);
    await tester.pumpAndSettle();
    expect(h.fact('posts', 'fetches=3'), findsOneWidget);
    expectBuilds(queryMembers, filtered: 6, plain: 8);
  });

  showcaseTest('leaving the screen releases all twelve query observers',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/build-when');
    expect(
      <int>[
        for (final query in h.client.queryCache.queries) query.observersCount,
      ],
      <int>[8, 4],
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('TanStack Query Showcase'), findsOneWidget);
    for (final query in h.client.queryCache.queries) {
      expect(query.observersCount, 0);
    }
  });
}
