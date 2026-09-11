/// The `max-pages` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/shared/theme.dart';

import '../harness.dart';

/// The rows sit in a bounded scroller, but the test font is a square per
/// glyph, so under it the facts wrap and the strip drops below the default
/// 600 px of a lazily built list. A taller surface keeps it built.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The cursors the backend answered, in order — one entry per page request.
List<String> cursors(Harness h) => <String>[
      for (final entry in h.backend.log)
        if (entry.method == 'GET' && entry.path == '/api/projects')
          entry.query['cursor']!,
    ];

/// Every `fetched hh:mm:ss` stamp on screen.
Set<String> stamps(WidgetTester tester) => tester
    .widgetList<Text>(find.textContaining('fetched '))
    .map((text) => text.data!)
    .toSet();

/// A button by its label, whichever kind it is.
Finder button(String label) => find.ancestor(
      of: find.text(label),
      matching: find.bySubtype<ButtonStyleButton>(),
    );

bool enabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(button(label)).enabled;

Future<void> press(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  showcaseTest('starts on the page at cursor 30 with both directions open',
      (tester, h) async {
    tall(tester);
    h.backend.latency = const Duration(milliseconds: 200);
    await h.open(tester, '/max-pages', settle: false);

    expect(find.byType(SkeletonBox), findsWidgets);
    expect(find.text('loading'), findsOneWidget);
    expect(find.text('pages=0'), findsOneWidget);
    expect(find.text('hasNextPage=false'), findsOneWidget);
    expect(enabled(tester, 'Load next'), isFalse);
    expect(h.fact('projects', 'status=pending'), findsOneWidget);
    expect(h.fact('projects', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonBox), findsNothing);
    expect(find.text('pages=1'), findsOneWidget);
    expect(find.text('pageParams=30'), findsOneWidget);
    expect(find.text('hasPreviousPage=true'), findsOneWidget);
    expect(find.text('hasNextPage=true'), findsOneWidget);
    expect(find.text('isFetchingPreviousPage=false'), findsOneWidget);
    expect(find.text('isFetchingNextPage=false'), findsOneWidget);
    expect(enabled(tester, 'Load previous'), isTrue);
    expect(enabled(tester, 'Load next'), isTrue);
    expect(find.text('Project 30'), findsOneWidget);
    expect(h.fact('projects', 'status=success'), findsOneWidget);
    expect(h.fact('projects', 'fetches=1'), findsOneWidget);
    expect(cursors(h), <String>['30']);
  });

  showcaseTest('a fourth page slides the window: the first one is dropped',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/max-pages');

    await press(tester, 'Load next');
    expect(find.text('pageParams=30,40'), findsOneWidget);
    await press(tester, 'Load next');
    expect(find.text('pages=3'), findsOneWidget);
    expect(find.text('pageParams=30,40,50'), findsOneWidget);
    expect(find.text('Project 30'), findsOneWidget);

    // Held back this time, so the direction shows while the page is fetched:
    // only the button in that direction is disabled.
    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(find.text('Load next'));
    await tester.pump();
    expect(find.text('loading next'), findsOneWidget);
    expect(find.text('isFetchingNextPage=true'), findsOneWidget);
    expect(find.text('isFetchingPreviousPage=false'), findsOneWidget);
    expect(enabled(tester, 'Load next'), isFalse);
    expect(enabled(tester, 'Load previous'), isTrue);
    expect(enabled(tester, 'Refetch'), isFalse);
    expect(h.fact('projects', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    // Three pages still, one at each end different: 30 fell off the front.
    expect(find.text('pages=3'), findsOneWidget);
    expect(find.text('pageParams=40,50,60'), findsOneWidget);
    expect(find.text('loading next'), findsNothing);
    expect(find.text('Project 30'), findsNothing);
    expect(find.text('Project 40'), findsOneWidget);

    // Every row is in the tree, so the far end of the window is provable
    // without scrolling: 60–69 arrived, 30–39 went.
    expect(find.text('Project 69'), findsOneWidget);
    expect(find.text('Project 39'), findsNothing);
    expect(find.textContaining('Project '), findsNWidgets(30));
    expect(cursors(h), <String>['30', '40', '50', '60']);
    expect(h.fact('projects', 'fetches=4'), findsOneWidget);
  });

  showcaseTest('load previous slides the window back and drops the far end',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/max-pages');
    for (var i = 0; i < 3; i++) {
      await press(tester, 'Load next');
    }
    expect(find.text('pageParams=40,50,60'), findsOneWidget);

    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(find.text('Load previous'));
    await tester.pump();
    expect(find.text('loading previous'), findsOneWidget);
    expect(find.text('isFetchingPreviousPage=true'), findsOneWidget);
    expect(find.text('isFetchingNextPage=false'), findsOneWidget);
    expect(enabled(tester, 'Load previous'), isFalse);
    expect(enabled(tester, 'Load next'), isTrue);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('pages=3'), findsOneWidget);
    expect(find.text('pageParams=30,40,50'), findsOneWidget);
    expect(find.text('Project 30'), findsOneWidget);
    // One new request, for the page that came back; 60 was simply dropped.
    expect(cursors(h), <String>['30', '40', '50', '60', '30']);
  });

  showcaseTest('a refetch re-requests exactly the pages in the window',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/max-pages');
    await press(tester, 'Load next');
    await press(tester, 'Load next');
    expect(find.text('pageParams=30,40,50'), findsOneWidget);
    expect(h.fact('projects', 'fetches=3'), findsOneWidget);
    final before = stamps(tester);
    expect(before, isNotEmpty);

    // The backend stamps every row with its clock, which is the test's fake
    // one: two seconds later the refetched rows carry a different stamp.
    await tester.pump(const Duration(seconds: 2));
    h.backend.log.clear();
    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(find.text('Refetch'));
    await tester.pump();
    expect(find.text('refreshing'), findsOneWidget);
    expect(find.text('isFetchingNextPage=false'), findsOneWidget);
    expect(find.text('isFetchingPreviousPage=false'), findsOneWidget);
    expect(enabled(tester, 'Refetch'), isFalse);
    // The rows stay on screen while the pages are refetched one by one.
    expect(find.text('Project 30'), findsOneWidget);

    // One page per latency, first to last.
    await tester.pump(const Duration(milliseconds: 200));
    expect(cursors(h), <String>['30']);
    await tester.pump(const Duration(milliseconds: 200));
    expect(cursors(h), <String>['30', '40']);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(cursors(h), <String>['30', '40', '50']);
    expect(find.text('refreshing'), findsNothing);
    expect(find.text('pageParams=30,40,50'), findsOneWidget);
    // One fetch, three requests: the strip counts fetches, not pages.
    expect(h.fact('projects', 'fetches=4'), findsOneWidget);
    expect(h.fact('projects', 'updates=4'), findsOneWidget);
    final after = stamps(tester);
    expect(after, isNotEmpty);
    expect(after.intersection(before), isEmpty);
  });

  showcaseTest('cursor 0 ends the backward direction and cursor 90 the forward',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/max-pages');

    for (var i = 0; i < 3; i++) {
      await press(tester, 'Load previous');
    }
    expect(find.text('pageParams=0,10,20'), findsOneWidget);
    expect(find.text('hasPreviousPage=false'), findsOneWidget);
    expect(find.text('hasNextPage=true'), findsOneWidget);
    expect(enabled(tester, 'Load previous'), isFalse);
    expect(enabled(tester, 'Load next'), isTrue);
    expect(find.text('Project 0'), findsOneWidget);
    expect(find.text('Project 29'), findsOneWidget);
    expect(find.text('Project 30'), findsNothing);

    for (var i = 0; i < 7; i++) {
      await press(tester, 'Load next');
    }
    expect(find.text('pageParams=70,80,90'), findsOneWidget);
    expect(find.text('hasNextPage=false'), findsOneWidget);
    expect(find.text('hasPreviousPage=true'), findsOneWidget);
    expect(enabled(tester, 'Load next'), isFalse);
    expect(enabled(tester, 'Load previous'), isTrue);

    expect(find.text('Project 99'), findsOneWidget);
    expect(find.text('Project 69'), findsNothing);
    expect(
      cursors(h),
      <String>['30', '20', '10', '0', '30', '40', '50', '60', '70', '80', '90'],
    );
  });

  showcaseTest(
      'the page context says which direction a fetch extends: forward, '
      'backward, and forward again for every page of a refetch',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/max-pages');
    // The first page has no other end to extend: it is forward.
    expect(find.text('lastPage=30 forward'), findsOneWidget);

    await press(tester, 'Load next');
    expect(find.text('lastPage=40 forward'), findsOneWidget);

    await press(tester, 'Load previous');
    expect(find.text('pageParams=20,30,40'), findsOneWidget);
    expect(find.text('lastPage=20 backward'), findsOneWidget);

    // A refetch walks the window first to last, each page forward: the last
    // one asked for is the window's last cursor.
    await press(tester, 'Refetch');
    expect(find.text('lastPage=40 forward'), findsOneWidget);
    expect(cursors(h), <String>['30', '40', '20', '20', '30', '40']);
  });

  showcaseTest('leaving the screen releases the observer', (tester, h) async {
    tall(tester);
    await h.open(tester, '/max-pages');
    expect(h.fact('projects', 'observers=1'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('TanStack Query Showcase'), findsOneWidget);
    expect(h.client.queryCache.queries.single.observersCount, 0);
  });
}
