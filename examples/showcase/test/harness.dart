/// What every feature's widget tests share: a fresh fake backend, a fresh
/// client, the real app opened on one route, and the teardown a
/// `QueryClient` needs.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:showcase/main.dart';
import 'package:showcase/shared/api.dart';

import 'fake_backend.dart';

class Harness {
  Harness({DefaultOptions? defaults, this.scenario = 'widget-test'})
      // On the shared notify manager, as `main.dart` builds the app's: the
      // `four-call-styles` screen batches through `NotifyManager.shared`.
      : client = QueryClient(
          defaultOptions: defaults,
          notifyManager: NotifyManager.shared,
        ) {
    api = ShowcaseApi(
      dio: Dio(BaseOptions(baseUrl: 'http://backend.test/api'))
        ..httpClientAdapter = backend,
      scenario: scenario,
    );
  }

  final FakeBackend backend = FakeBackend();
  final QueryClient client;
  final String scenario;
  late final ShowcaseApi api;

  /// Pumps the app on [route]. With [settle] the first fetch has landed; pass
  /// `false` to look at the first frame.
  Future<void> open(WidgetTester tester, String route,
      {bool settle = true}) async {
    await tester.pumpWidget(
      ShowcaseApp(api: api, client: client, initialRoute: route),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
  }

  /// How many requests the backend answered for [method] and [path]
  /// (`/api/...`, exact or a `RegExp`).
  int requests(String method, Pattern path) => backend.count(method, path);

  /// The debug strip labelled [label]: the group named `debug <label>`.
  Finder strip(String label) => groupNamed('debug $label');

  /// One fact inside the strip, by its exact text: `fetchStatus=idle`.
  Finder fact(String label, String text) => factIn('debug $label', text);
}

/// The semantics group named [name], by the key `SemanticsGroup` derives from
/// that one name (`lib/shared/fact_group.dart`).
///
/// The same string the end-to-end suite passes to
/// `getByRole('group', { name })`, so a group is addressed by one name in both
/// layers and a screen spells it once (C56, #51).
Finder groupNamed(String name) => find.byKey(ValueKey<String>(name));

/// One fact inside the group named [name], by its exact text.
///
/// `status=success` is said by a reader's facts and by a strip alike, so a
/// lookup always names which group it means.
Finder factIn(String name, String text) =>
    find.descendant(of: groupNamed(name), matching: find.text(text));

/// `testWidgets` plus the cleanup a `QueryClient` needs: it owns `gcTime`
/// timers, and the test binding checks for pending timers before any
/// `tearDown` runs. The teardown is the documented one (ADR-0002, the site's
/// testing guide), in its order.
///
/// Screens that poll or retry must be stepped with `tester.pump(duration)`;
/// `pumpAndSettle` never returns while a `refetchInterval` is running.
void showcaseTest(
  String description,
  Future<void> Function(WidgetTester tester, Harness h) body, {
  DefaultOptions? defaults,
}) {
  testWidgets(description, (tester) async {
    final h = Harness(defaults: defaults);
    try {
      await body(tester, h);
    } finally {
      // Tear the tree down first, then let the frame after it run: the
      // binding's `context.query` scope releases observers in a post-frame
      // sweep, and clearing the client before that runs would leave the
      // sweep to re-create what it is about to drop.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      h.client.clear();
      // A mutation the clear dropped fails a few microtasks later and its
      // callbacks run then; an optimistic rollback's `setQueryData` re-creates
      // the query it names, gc timer included. Let them run, clear once more.
      await tester.pump();
      h.client.clear();
      h.backend.close();
    }
  });
}
