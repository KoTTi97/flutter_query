---
title: Testing
sidebar_position: 9
description: queryWidgetTest, why a widget test needs a teardown at all, and the pump rules that fake timers impose.
---

# Testing

A `QueryClient` outlives the widget tree by design — it owns the cache and its
`gcTime` timers. Flutter's test binding asserts that **no timer is pending**
when the tree comes down, and it checks that *before* any `tearDown` runs, so
the cleanup has to happen inside the test body.

Get it wrong and the test fails with a pending-timer error that says nothing
about queries. That is a poor first hour with any library, so the fix ships as
API rather than as a snippet.

## `queryWidgetTest`

```dart
import 'package:query_kit_flutter/testing.dart';

void main() {
  queryWidgetTest('the list loads', (tester, client) async {
    await tester.pumpWidget(QueryClientProvider(
      client: client,
      child: const MaterialApp(home: TasksScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Task a'), findsOneWidget);
  });
}
```

The client is built for the case and taken down after it. Pass `createClient`
to give it `defaultOptions`; the remaining arguments (`skip`, `timeout`,
`variant`, `tags`, `semanticsEnabled`) are `testWidgets`'s own.

:::warning Import it from `test/` only
`package:query_kit_flutter/testing.dart` pulls in `flutter_test`. Never import
it from `lib/`.
:::

## Doing it yourself

For a test that builds its own clients, or drives more than one,
`tearDownQueryClient(tester, client)` is the same steps on their own:

```dart
await tester.pumpWidget(const SizedBox()); // let the widgets go
await tester.pumpAndSettle();              // and the frame after them run
client.clear();                            // then the cache and its timers
await tester.pump();                       // let a dropped mutation's callbacks run
client.clear();                            // and what they wrote go too
```

The last two matter when a test leaves a mutation paused offline: `clear()`
fails it, its `onError` runs a moment later, and an optimistic rollback's
`setQueryData` re-creates the query it names — gc timer included.

## The pump rules

Two things surprise people, and both come from `testWidgets` running under
`FakeAsync`.

**`pumpAndSettle` only pumps while a frame is scheduled.** A fake backend's
latency is a *timer*, not a frame, and so is a `refetchInterval`. Step them
explicitly:

```dart
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

That is the same property the core's own suite relies on; there, tests use
`testFakeAsync` from `test/test_utils.dart` rather than bare `fakeAsync`,
because `FakeAsync.elapse` cannot be called re-entrantly.

## Testing without widgets

A `QueryController` is a plain `ValueListenable`, and the core's
`QueryObserver` is a plain object with `subscribe`. Both are testable with
`package:test` alone, no binding required — which is often the faster way to
pin a cache behaviour down.

## What the examples do

Both example apps wrap the same helper with their own fixture —
`showcaseTest` in `examples/showcase/test/harness.dart`, which also brings a
fresh fake backend and opens the app on one route. They are worth reading
before writing your own harness; the showcase's README lists the rules that
cost someone a debugging session, in the order they bite.
