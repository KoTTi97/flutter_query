/// The `mutation-state` screen against the fake backend.
///
/// What each case pins down about `MutationStateController`: it sees
/// mutations nobody on screen owns, counts two concurrent runs under one key
/// as two, tells an error apart from a pending run, and does not rebuild when
/// the selection came out equal.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../harness.dart';

/// The badge sits under the buttons and above the strip; the test font is a
/// square per glyph, so a taller surface keeps all of it built.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  showcaseTest('the badge starts empty and owns nothing', (tester, h) async {
    tall(tester);
    await h.open(tester, '/mutation-state');

    expect(find.text('saving=0'), findsOneWidget);
    expect(find.text('failed=0'), findsOneWidget);
    expect(find.text('tracked=0'), findsOneWidget);
  });

  showcaseTest('two concurrent runs under one key count as two',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/mutation-state');

    // The screen's own delay holds both requests open; press twice before
    // either can answer.
    await tester.tap(find.text('Add todo'));
    await tester.pump();
    await tester.tap(find.text('Add todo'));
    await tester.pump();

    expect(find.text('saving=2'), findsOneWidget);
    expect(find.text('tracked=2'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Let both land, plus the invalidation they trigger.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('saving=0'), findsOneWidget);
    expect(find.text('failed=0'), findsOneWidget);
    expect(h.requests('POST', '/api/todos'), 2);
  });

  showcaseTest('a failing run is an error, not a pending one',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/mutation-state');

    await tester.tap(find.text('Add, failing'));
    await tester.pump();
    expect(find.text('saving=1'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('saving=0'), findsOneWidget);
    expect(find.text('failed=1'), findsOneWidget);
  });

  showcaseTest('an unrelated cache event does not rebuild the badge',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/mutation-state');

    final before = tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && w.data!.startsWith('badge-builds=')));

    // A query write is a cache event the badge's filter does not select.
    h.client.setQueryData<List<Object?>>(
        QueryKey(const <Object?>['unrelated']), const <Object?>[]);
    await tester.pumpAndSettle();

    final after = tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && w.data!.startsWith('badge-builds=')));
    expect(after.data, before.data,
        reason: 'the mutation selection did not change, so nothing rebuilt');
  });
}
