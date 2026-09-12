/// The `stale-and-gc` screen against the fake backend.
///
/// Time under `testWidgets` is fake and `clock` is bound to it, so
/// `pump(Duration(seconds: 5))` really ages the data and fires the observer's
/// stale timer and the entry's gc timer.
library;

import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// One of the reader's own facts (`reader=attached`, `serial=1`,
/// `isStale=true`) — scoped, because the strip shows an `isStale=` of its own.
Finder reader(String text) => factIn('reader', text);

/// A segment of the stale-time or the gc-time button, by its label — both
/// have a `5 s`.
Finder segment(String group, String label) => factIn(group, label);

Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}

/// Detaches and re-attaches the reader: a fresh observer, so a mount.
Future<void> reattach(WidgetTester tester) async {
  await tapTooltip(tester, 'Detach reader');
  expect(reader('reader=detached'), findsOneWidget);
  await tapTooltip(tester, 'Attach reader');
  expect(reader('reader=attached'), findsOneWidget);
}

void main() {
  showcaseTest('zero: stale the moment it arrives, and a re-attach refetches',
      (tester, h) async {
    await h.open(tester, '/stale-and-gc');

    expect(reader('serial=1'), findsOneWidget);
    expect(reader('isStale=true'), findsOneWidget);
    expect(h.fact('time', 'fetches=1'), findsOneWidget);

    await tapTooltip(tester, 'Detach reader');
    expect(h.fact('time', 'observers=0'), findsOneWidget);
    await tapTooltip(tester, 'Attach reader');

    expect(reader('serial=2'), findsOneWidget);
    expect(h.fact('time', 'fetches=2'), findsOneWidget);
    expect(h.fact('time', 'observers=1'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 2);
  });

  showcaseTest(
      '5 s: fresh, stale after five seconds, and a re-attach refetches only '
      'once stale', (tester, h) async {
    await h.open(tester, '/stale-and-gc');
    await tester.tap(segment('stale-time', '5 s'));
    await tester.pumpAndSettle();
    expect(reader('isStale=false'), findsOneWidget);

    // Within the five seconds a mount finds fresh data and leaves it alone.
    await reattach(tester);
    expect(reader('serial=1'), findsOneWidget);
    expect(h.fact('time', 'fetches=1'), findsOneWidget);

    // The observer's stale timer flips the result without any fetch.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(reader('isStale=true'), findsOneWidget);
    expect(h.fact('time', 'fetches=1'), findsOneWidget);

    await reattach(tester);
    expect(reader('serial=2'), findsOneWidget);
    expect(reader('isStale=false'), findsOneWidget);
    expect(h.fact('time', 'fetches=2'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 2);
  });

  showcaseTest(
      'static: neither a re-attach nor an invalidation fetches; Refetch does',
      (tester, h) async {
    await h.open(tester, '/stale-and-gc');
    await tester.tap(segment('stale-time', 'static'));
    await tester.pumpAndSettle();
    expect(reader('isStale=false'), findsOneWidget);

    await reattach(tester);
    expect(h.fact('time', 'fetches=1'), findsOneWidget);

    // The invalidation is recorded on the entry but outranked: the data
    // stays fresh and `refetchQueries` skips a static query.
    await tapTooltip(tester, 'Invalidate');
    expect(reader('isStale=false'), findsOneWidget);
    expect(h.fact('time', 'isStale=false'), findsOneWidget);
    expect(h.fact('time', 'fetches=1'), findsOneWidget);

    // The observer's own `refetch()` is a request, not a trigger.
    await tapTooltip(tester, 'Refetch');
    expect(reader('serial=2'), findsOneWidget);
    expect(h.fact('time', 'fetches=2'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 2);
  });

  showcaseTest(
      'infinite: a re-attach does not fetch; an invalidation and Refetch do',
      (tester, h) async {
    await h.open(tester, '/stale-and-gc');
    await tester.tap(segment('stale-time', 'infinite'));
    await tester.pumpAndSettle();
    expect(reader('isStale=false'), findsOneWidget);

    await reattach(tester);
    expect(h.fact('time', 'fetches=1'), findsOneWidget);

    await tapTooltip(tester, 'Invalidate');
    expect(reader('serial=2'), findsOneWidget);
    expect(reader('isStale=false'), findsOneWidget);
    expect(h.fact('time', 'fetches=2'), findsOneWidget);

    await tapTooltip(tester, 'Refetch');
    expect(reader('serial=3'), findsOneWidget);
    expect(h.fact('time', 'fetches=3'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 3);
  });

  showcaseTest(
      'invalidate: refetched at once while attached, on the next attach '
      'while detached', (tester, h) async {
    await h.open(tester, '/stale-and-gc');
    await tester.tap(segment('stale-time', '5 s'));
    await tester.pumpAndSettle();
    expect(reader('isStale=false'), findsOneWidget);

    await tapTooltip(tester, 'Invalidate');
    expect(reader('serial=2'), findsOneWidget);
    expect(h.fact('time', 'fetches=2'), findsOneWidget);

    // Nobody reads the entry, so nothing refetches; the mark stays, and the
    // next mount honours it although the five seconds have not passed.
    await tapTooltip(tester, 'Detach reader');
    await tapTooltip(tester, 'Invalidate');
    expect(h.fact('time', 'isStale=true'), findsOneWidget);
    expect(h.fact('time', 'fetches=2'), findsOneWidget);

    await tapTooltip(tester, 'Attach reader');
    expect(reader('serial=3'), findsOneWidget);
    expect(reader('isStale=false'), findsOneWidget);
    expect(h.fact('time', 'fetches=3'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 3);
  });

  showcaseTest(
      'gc 5 s: a detached entry is collected, and the next attach starts '
      'from scratch', (tester, h) async {
    await h.open(tester, '/stale-and-gc');
    await tapTooltip(tester, 'Detach reader');
    expect(h.fact('time', 'status=success'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(h.fact('time', 'status=absent'), findsOneWidget);

    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(find.byTooltip('Attach reader'));
    await tester.pump();
    expect(h.fact('time', 'status=pending'), findsOneWidget);
    expect(reader('reader=attached'), findsOneWidget);
    expect(reader('serial=1'), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(h.fact('time', 'status=success'), findsOneWidget);
    expect(reader('serial=2'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 2);
  });

  showcaseTest('gc never: a detached entry is still there ten minutes later',
      (tester, h) async {
    await h.open(tester, '/stale-and-gc');
    await tester.tap(segment('gc-time', 'never'));
    await tester.pumpAndSettle();
    await tapTooltip(tester, 'Detach reader');

    await tester.pump(const Duration(minutes: 10));
    await tester.pumpAndSettle();
    expect(h.fact('time', 'status=success'), findsOneWidget);
    expect(h.fact('time', 'observers=0'), findsOneWidget);

    // Back from `never` only by removing the entry: the gc time an entry
    // keeps is the longest any reader ever gave it.
    await tester.tap(segment('gc-time', '5 s'));
    await tester.pumpAndSettle();
    await tapTooltip(tester, 'Remove entry');
    expect(h.fact('time', 'status=absent'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 1);
  });

  showcaseTest('dynamic: fresh after an odd serial, stale after an even one',
      (tester, h) async {
    await h.open(tester, '/stale-and-gc');
    await tester.tap(segment('stale-time', 'dynamic'));
    await tester.pumpAndSettle();
    expect(reader('serial=1'), findsOneWidget);
    expect(reader('isStale=false'), findsOneWidget);

    await tapTooltip(tester, 'Refetch');
    expect(reader('serial=2'), findsOneWidget);
    expect(reader('isStale=true'), findsOneWidget);

    await tapTooltip(tester, 'Refetch');
    expect(reader('serial=3'), findsOneWidget);
    expect(reader('isStale=false'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 3);
  });
}
