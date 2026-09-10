/// The `query-collections` screen against the fake backend.
///
/// What each case pins down about `QueriesObserver`: the collection fetches
/// every member once, reordering it starts nothing, growing it fetches only
/// what is new, shrinking it releases what left, a duplicate id shares the
/// one cache entry, and one member's failure is its own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/shared/api.dart';
import 'package:showcase/shared/models.dart';

import '../harness.dart';

/// The strips stack up under the cards, and the test font is a square per
/// glyph, so the default 600 px surface would leave the later ones unbuilt.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  showcaseTest('the collection fetches every member exactly once',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/query-collections');

    expect(find.text('ids=1,2,3'), findsOneWidget);
    for (final id in <int>[1, 2, 3]) {
      expect(h.fact('post-$id', 'status=success'), findsOneWidget);
      expect(h.fact('post-$id', 'observers=1'), findsOneWidget);
      expect(h.requests('GET', '/api/posts/$id'), 1);
    }
    // Selected down to the title: the collection is homogeneous in String.
    expect(find.text('Window contact: setup guide'), findsOneWidget);
  });

  showcaseTest('reordering reuses every observer and starts no request',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/query-collections');

    await tester.tap(find.text('Reverse'));
    await tester.pumpAndSettle();

    expect(find.text('ids=3,2,1'), findsOneWidget);
    for (final id in <int>[1, 2, 3]) {
      // Reused by key and occurrence: same observer, same entry, no refetch.
      expect(h.requests('GET', '/api/posts/$id'), 1);
      expect(h.fact('post-$id', 'observers=1'), findsOneWidget);
      expect(h.fact('post-$id', 'fetches=1'), findsOneWidget);
    }
    // The order the builder rendered is the order it was handed.
    expect(find.text('#1 — post 3'), findsOneWidget);
    expect(find.text('#3 — post 1'), findsOneWidget);
  });

  showcaseTest('growing fetches only the new member', (tester, h) async {
    tall(tester);
    await h.open(tester, '/query-collections');

    await tester.tap(find.text('Add post'));
    await tester.pumpAndSettle();

    expect(find.text('ids=1,2,3,4'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/4'), 1);
    for (final id in <int>[1, 2, 3]) {
      expect(h.requests('GET', '/api/posts/$id'), 1);
    }
  });

  showcaseTest('shrinking releases the observer that left', (tester, h) async {
    tall(tester);
    await h.open(tester, '/query-collections');

    await tester.tap(find.text('Remove last'));
    await tester.pumpAndSettle();

    expect(find.text('ids=1,2'), findsOneWidget);
    expect(h.fact('post-3', 'observers=0'), findsOneWidget);
    expect(h.fact('post-1', 'observers=1'), findsOneWidget);
  });

  showcaseTest('a duplicate id shares one entry with two observers',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/query-collections');

    await tester.tap(find.text('Duplicate first'));
    await tester.pumpAndSettle();

    expect(find.text('ids=1,2,3,1'), findsOneWidget);
    // Two observers over one cache entry — the duplicate did not get an
    // entry of its own.
    expect(h.fact('post-1', 'observers=2'), findsOneWidget);
    // The newcomer found a stale entry (staleTime defaults to zero) and so
    // refetched it, upstream's rule for a mounting observer. The point is
    // that this is ONE shared refetch, not one per observer.
    expect(h.requests('GET', '/api/posts/1'), 2);
    expect(h.fact('post-1', 'fetches=2'), findsOneWidget);
    // The untouched neighbours prove the refetch was the entry's, not the
    // collection's.
    expect(h.requests('GET', '/api/posts/2'), 1);
    expect(find.text('#1 — post 1'), findsOneWidget);
    expect(find.text('#4 — post 1'), findsOneWidget);
  });

  showcaseTest('one member fails alone', (tester, h) async {
    tall(tester);
    await h.open(tester, '/query-collections');

    await tester.tap(find.text('Add missing id'));
    await tester.pumpAndSettle();

    expect(find.text('ids=1,2,3,999'), findsOneWidget);
    expect(h.fact('post-999', 'status=error'), findsOneWidget);
    // The neighbours are untouched by it.
    for (final id in <int>[1, 2, 3]) {
      expect(h.fact('post-$id', 'status=success'), findsOneWidget);
    }
    expect(find.text('Window contact: setup guide'), findsOneWidget);
  });

  showcaseTest('leaving the screen releases every observer', (tester, h) async {
    tall(tester);
    await h.open(tester, '/query-collections');

    await tester.pageBack();
    await tester.pumpAndSettle();

    for (final id in <int>[1, 2, 3]) {
      expect(
          h.client.queryCache.get<Post>(ShowcaseKeys.post(id))!.observersCount,
          0);
    }
  });
}
