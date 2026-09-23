---
title: Testing
description: The teardown every widget test needs, a harness that wraps it, a client without retries, and the pump rules that fake timers impose.
---

{/* depth: todo */}

# Testing

## The teardown every widget test needs

A `QueryClient` outlives the widget tree by design — it owns the cache and its
`gcTime` timers. Flutter's test binding asserts that **no timer is pending**
when the tree comes down, and it checks that *before* any `tearDown` runs, so
the cleanup has to happen inside the test body. Get it wrong and the test
fails with a pending-timer error that says nothing about queries. The end of
a query widget test is therefore always the same steps:

```dart snippet="guides/testing.md#teardown"
testWidgets('the list loads', (tester) async {
  final client = QueryClient();
  await tester.pumpWidget(QueryClientProvider(
    client: client,
    child: const MaterialApp(home: TasksScreen()),
  ));
  await tester.pumpAndSettle();
  expect(find.byType(ListView), findsOneWidget);

  // Let the widgets go, and the frame after them run.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  // Then the cache and its timers.
  client.clear();
  // A mutation the clear dropped fails a moment later and its callbacks
  // run then; let them, then clear what they wrote.
  await tester.pump();
  client.clear();
});
```

Tear the tree down first and let the frame after it run: the binding's
`context.query` scope releases observers in a post-frame sweep, and clearing
the client before that runs would leave the sweep to re-create what it is
about to drop. Then `clear()` cancels the `gcTime` timers. The last two steps
matter when a test leaves a mutation paused offline: `clear()` fails it, its
`onError` runs a moment later, and an optimistic rollback's `setQueryData`
re-creates the query it names — gc timer included.

Nothing here is exported by the package. `flutter_test` is a dev dependency
of `query_kit_flutter`, not a regular one, so nothing a test needs sits in
your app's dependency graph. Copy the steps, or the harness below, into your
own test folder. The samples on this page are the cases of
[`examples/doc_snippets/test/teardown_snippet_test.dart`](https://github.com/KoTTi97/flutter_query/blob/main/examples/doc_snippets/test/teardown_snippet_test.dart),
which CI runs, so they cannot rot.

## A harness

Written once per test suite, so no case repeats the steps:

```dart snippet="guides/testing.md#harness"
/// `testWidgets` plus the teardown a `QueryClient` needs.
void queryWidgetTest(
  String description,
  Future<void> Function(WidgetTester tester, QueryClient client) body, {
  QueryClient Function()? createClient,
}) {
  testWidgets(description, (tester) async {
    final client = (createClient ?? QueryClient.new)();
    try {
      await body(tester, client);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      client.clear();
      await tester.pump();
      client.clear();
    }
  });
}
```

The client is built for the case and taken down after it; pass `createClient`
to give it `defaultOptions`. A case then reads as the first sample without
its last five lines:

```dart snippet="guides/testing.md#using-the-harness"
queryWidgetTest('the list loads', (tester, client) async {
  await tester.pumpWidget(QueryClientProvider(
    client: client,
    child: const MaterialApp(home: TasksScreen()),
  ));
  await tester.pumpAndSettle();
  expect(find.byType(ListView), findsOneWidget);
});
```

Both example apps wrap this shape with a fixture of their own, in the same
teardown order: `showcaseTest` in
[`examples/showcase/test/harness.dart`](https://github.com/KoTTi97/flutter_query/blob/main/examples/showcase/test/harness.dart),
which also brings a fresh fake backend and opens the app on one route, and
`demoTest` in
[`examples/task_manager/test/acceptance_test.dart`](https://github.com/KoTTi97/flutter_query/blob/main/examples/task_manager/test/acceptance_test.dart).
The binding's own suite has the fuller version in
[`packages/query_kit_flutter/test/harness.dart`](https://github.com/KoTTi97/flutter_query/blob/main/packages/query_kit_flutter/test/harness.dart)
— a second client adopted for the teardown, the provider wired with lifecycle
observation off, the app lifecycle put back to `resumed` when a case faked
it. None of them is importable; they are worth reading before you write your
own.

## A client for tests

The default retries — three, with backoff — make a failing query take seven
seconds to fail. A test's client turns them off:

```dart snippet="guides/testing.md#no-retries"
QueryClient testClient() => QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(retry: RetryPolicy.never),
      ),
    );
```

Pass it as the harness's `createClient: testClient`. Mutations already default
to no retries. Build a **new client per test**: a shared one carries cached
data from one case into the next.

## Faking the backend

Fake the transport, not the library. The query functions under test call
your API client; hand them one that answers from memory — an interface with a
fake implementation, or your HTTP client's own mocking adapter. The cache
then behaves exactly as it does in the app: retries, staleness, structural
sharing and all.

Give the fake a latency (a `Future.delayed`) when a test is about the loading
state, and step it as below.

## The pump rules

Two things surprise people, and both come from `testWidgets` running under
`FakeAsync`.

**`pumpAndSettle` only pumps while a frame is scheduled.** A fake backend's
latency is a *timer*, not a frame, and so is a `refetchInterval`. Step them
explicitly:

```dart snippet="guides/testing.md#stepping-a-fake"
await tester.pump(const Duration(milliseconds: 300)); // the fake's latency
await tester.pumpAndSettle();
```

A screen that polls or retries never settles at all — `pumpAndSettle` will time
out. Drive those with `pump(duration)` only.

**`tester.pump()` with no duration does not let a `dio` response resolve.**
`dio` hangs its pipeline off zero-duration timers, and `FakeAsync` runs those
only when the clock moves. Step with a real duration.

## Time is fake, and `clock` is bound to it

The whole library reads time through `package:clock`, and `testWidgets` binds
`clock` to the fake one. So `pump(const Duration(minutes: 5))` genuinely ages
data past its `staleTime` and fires `gcTime` timers — no `withClock`, no
sleeping, no flake.

Outside `testWidgets`, `fakeAsync` from `package:fake_async` does the same
for the core: `clock` follows its fake time, and `async.elapse(duration)`
fires the timers.

## Testing without widgets

A `QueryController` is a plain `ValueListenable`, and the core's
`QueryObserver` is a plain object with `subscribe`. Both are testable with
plain `test()` cases, no `WidgetTester` required — a `QueryController` under
`flutter test`, a `QueryObserver` even under `dart test` — which is often the
faster way to pin a cache behaviour down.
