/// What every widget test in this suite shares: a client per case, the
/// provider wired around the widget under test, and the teardown a
/// `QueryClient` needs — once, in the order the testing guide documents.
///
/// The teardown is the documented snippet, not an export of the package
/// (ADR-0002, https://github.com/KoTTi97/flutter_query/issues/42): a
/// `QueryClient` outlives the widget tree and owns the `gcTime` timers of
/// everything in its cache, and Flutter's test binding asserts that no timer
/// is pending when the tree comes down — *before* any `tearDown` runs. So the
/// cleanup happens inside the test body, and it is the same steps every
/// time:
///
/// 1. `pumpWidget(const SizedBox())` — let the widgets go;
/// 2. `pumpAndSettle()` — and the frame after them run, where an observer a
///    `context.query` reader released is dropped by the post-frame sweep;
/// 3. `client.clear()` — then the cache and its timers;
/// 4. `pump()` — a mutation the clear dropped fails a few microtasks later
///    and its callbacks run then: an offline optimistic update's rollback
///    writes the previous value back with `setQueryData`, re-creating the
///    query it names, gc timer included (ninth review, C11);
/// 5. `client.clear()` — and what they wrote goes too.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

/// [testWidgets] for a tree with a [QueryClient] in it: builds a client for
/// the case, hands it to [body], and takes it down afterwards — together with
/// every client the case adopted through [HarnessTester.adopt].
///
/// [createClient] builds the client — pass one to set `defaultOptions`. The
/// remaining arguments are [testWidgets]'s own and mean the same thing.
@isTest
void queryWidgetTest(
  String description,
  Future<void> Function(WidgetTester tester, QueryClient client) body, {
  QueryClient Function()? createClient,
  bool? skip,
  Timeout? timeout,
  bool semanticsEnabled = true,
  TestVariant<Object?> variant = const DefaultTestVariant(),
  dynamic tags,
}) {
  testWidgets(
    description,
    (tester) async {
      final client = (createClient ?? QueryClient.new)();
      try {
        await body(tester, client);
      } finally {
        await tearDownQueryClients(
          tester,
          <QueryClient>[client, ...?_adopted[tester]],
        );
      }
    },
    skip: skip,
    timeout: timeout,
    semanticsEnabled: semanticsEnabled,
    variant: variant,
    tags: tags,
  );
}

/// The documented teardown, for every client a case drove.
///
/// Tears the tree down, lets the frame after it run, clears each client,
/// lets a dropped mutation's callbacks run, and clears each once more. A
/// case that faked the app lifecycle and left it somewhere other than
/// `resumed` is put back, so the next case starts where a test binding
/// otherwise would.
Future<void> tearDownQueryClients(
  WidgetTester tester,
  Iterable<QueryClient> clients,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  for (final client in clients) {
    client.clear();
  }
  await tester.pump();
  for (final client in clients) {
    client.clear();
  }
  if (tester.binding.lifecycleState case final state?
      when state != AppLifecycleState.resumed) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

/// The provider wired around [child]: a `QueryClientProvider` for [client]
/// inside a `MaterialApp` scaffold.
///
/// Lifecycle observation is off unless a case asks for it: most cases drive
/// the focus manager directly, and the ones that fake the app lifecycle
/// through `tester.binding.handleAppLifecycleStateChanged` build their own
/// provider so the mapping under test is in plain sight.
Widget app(
  QueryClient client,
  Widget child, {
  bool observeAppLifecycle = false,
  OnlineStatus? onlineStatus,
}) =>
    QueryClientProvider(
      client: client,
      observeAppLifecycle: observeAppLifecycle,
      onlineStatus: onlineStatus,
      child: MaterialApp(home: Scaffold(body: child)),
    );

final Expando<List<QueryClient>> _adopted = Expando<List<QueryClient>>();

extension HarnessTester on WidgetTester {
  /// Pumps [child] under [app] for [client].
  Future<void> pumpApp(QueryClient client, Widget child) =>
      pumpWidget(app(client, child));

  /// Registers a client the case built itself — a second one to switch to,
  /// a subclass that counts its clears — for the teardown
  /// [queryWidgetTest] runs. Returns it, so it reads as a declaration.
  T adopt<T extends QueryClient>(T client) {
    (_adopted[this] ??= <QueryClient>[]).add(client);
    return client;
  }
}
