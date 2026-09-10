# tanstack_query_flutter

The Flutter binding for [`tanstack_query_core`](https://pub.dev/packages/tanstack_query_core) — a
`QueryClientProvider`, listenable controllers, builder widgets, a `State` mixin
and `context.query(...)`.

**No dependency beyond Flutter itself.** Not `flutter_hooks`, not a signals
package, not `connectivity_plus`. You should not have to adopt somebody's state
management to use a cache.

> An independent community port. Not affiliated with, endorsed by, or a product
> of TanStack.

## Four equal ways to read a query

They are layered, not competing: each is a thin shell over the one below, and
they interoperate inside one screen. **There is no recommended default** — pick
per situation.

### `context.query(...)`

```dart
class SensorScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sensor = context.query(sensorQuery(id));
    return switch (sensor) {
      QueryPending() => const CircularProgressIndicator(),
      QuerySuccess(:final data) => SensorCard(data),
      QueryError(:final error) => ErrorBanner(error),
    };
  }
}
```

Flat, works in a `StatelessWidget`, and **rebuilds only the widgets that read
that query** — a change to one query does not touch the rest of the screen. The
most machinery behind the curtain. Each reading widget gets observers of its
own (what is shared is the query in the cache, which the core deduplicates), and
they are released when the widget stops reading the key or unmounts. A widget
that stops calling `context.query` *altogether* gives no signal Flutter can
see, so its last observers stay until it unmounts — put a conditional read in
its own small widget. Read in `build`, not in a handler: the read is reconciled
against the previous build. `context.selectQuery` is the form with a `select`
whose output type differs from the cache's. `context.query` always reads the
provider's client and takes no `client:` — a `BuildContext` names exactly one
provider; for a client that is not the provider's, use the builders (`client:`)
or the controllers, or override `queryClient` on a `QueryMixin` State.

### `QueryBuilder`

```dart
QueryBuilder<Sensor>(
  options: sensorQuery(id),
  builder: (context, result) => switch (result) { … },
)
```

The `StreamBuilder` shape. The most explicit and the most predictable —
everything is visible in the tree — and the natural fit inside a list or a
sliver. Several queries on one screen means several nested builders.
`QuerySelectBuilder<TQueryData, TData>` is the same widget for a query with a
`select` whose output type differs from the cache's.

### `QueryMixin`

```dart
class _SensorScreenState extends State<SensorScreen> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final sensor = watchQuery(sensorQuery(widget.id));
    final rename = watchMutation(renameSensor());
    …
  }
}
```

Flat like `context.query`, owned by the `State`. Entries are identified by their
`QueryKey` and types, not by call order, so `watchQuery` inside an `if` is fine —
there is no equivalent of the rules of hooks. A key read in the previous build
but not in this one is released after the frame, as with `context.query`. Two
reads of one key with different selectors of the same output type, or two
mutations of the same shape, are told apart by an `id:` argument — and reading
two of them *without* one is caught by an assertion in debug builds. An `id:`
is then the read's identity: a read that carries one keeps its observer when
its key changes, the way upstream's one-observer-per-call-site does, so
`PlaceholderData.compute((previous, _) => previous)` shows the previous key's
data while the next loads. Without an `id:`, a new key is a new observer and
the placeholder has nothing previous to show.

### `QueryController`

```dart
final sensor = QueryController.create(client, sensorQuery(id));   // no select
// … sensor.value, sensor.addListener, sensor.refetch() …
sensor.dispose();
```

`QueryController<TQueryData, TData>(client, options)` is the form with a
`select` whose output type differs from the cache's.

A `ValueListenable<QueryResult<T>>`. Nothing hidden, testable without widgets,
and the foundation the other three stand on. Its `value` before the first
listener is the optimistic result — `fetching` for a query that will fetch on
subscribe — the same thing a widget sees on its first build. Because it is a plain listenable,
it also drops into `ValueListenableBuilder`, `ListenableBuilder`,
`Listenable.merge`, `provider`, `riverpod` and `bloc` unchanged.

## Infinite queries and mutations

The same four shapes. Paging lives on the controller, which is what every style
hands back for an infinite query:

```dart
final feed = context.infiniteQuery(feedQuery());      // or watchInfiniteQuery,
// InfiniteQueryBuilder(builder: (context, feed) => …), InfiniteQueryController
final pages = feed.value.dataOrNull?.pages ?? const [];
if (feed.hasNextPage) feed.fetchNextPage();
```

Mutations likewise: `context.mutation(...)`, `watchMutation(...)`,
`MutationBuilder`, `MutationController`. A mutation is owned by the widget that
asks for it and disposed with it. In the context and mixin styles a mutation is
identified by `id`, else by its `mutationKey`, each together with its three
type arguments; without either, by the types alone. Like a query, it is released
after the frame once a build stops reading it.

The third type argument is what `onMutate` returns — the rollback handle of an
optimistic update. A mutation without one uses `MutationOptions.simple`, which
fixes it to `void` and lets the other two infer from `mutationFn`:

```dart
final add = context.mutation(MutationOptions.simple(
  mutationFn: (String name) => api.add(name),
  onSuccess: (_, __, ___) => client.invalidateQueries(
    filters: QueryFilters(queryKey: sensorsKey),
  ),
));
```

## Side effects, and lists of queries

Two widgets sit beside the four styles rather than among them, because neither
is a way of *reading* a query.

`QueryListener`, `InfiniteQueryListener` and `MutationListener` run a callback
on a controller they **borrow** — the owner still disposes it — and never
rebuild their `child`. Nothing fires on mount, only later transitions, and
callbacks are delivered off the build phase, so navigating or showing a
snackbar from one is safe:

```dart
QueryListener<Sensor, Sensor>(
  controller: sensor,
  listenWhen: (previous, next) => previous.errorOrNull != next.errorOrNull,
  listener: (context, result) => ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Sensor unreachable'))),
  child: const SensorTile(),
)
```

A rejected `listenWhen` still advances the comparison state, so the next
callback sees the transition it actually followed.

`QueriesBuilder` observes a list of queries that may change length or order.
Observers are reused by key and occurrence, so reordering starts no requests,
and duplicate keys share one cache entry while keeping their own options:

```dart
QueriesBuilder<Sensor, String>(
  queries: [
    for (final id in visibleIds)
      QueryObserverOptions<Sensor, String>(
        queryKey: QueryKey(<Object?>['sensors', id]),
        queryFn: (context) => api.getSensor(id, signal: context.signal),
        select: (sensor) => sensor.name,
      ),
  ],
  builder: (context, results) => Column(children: [
    for (final result in results) Text(result.dataOrNull ?? '…'),
  ]),
)
```

Each query fails and settles on its own; one error does not disturb its
neighbours. `MutationStateController` is the matching read over the mutation
cache — every mutation matching a filter, through a `select` — for a "saving…"
badge that no single widget owns.

## What rebuilds, and when

The rule is upstream's: **a widget rebuilds whenever its result changes**, and
a background refetch that brings back equal data is still a change, because
`dataUpdatedAt` moved. Two tools narrow that down.

`select` narrows the **data** a widget sees. A fetch that brings back data
whose selection is equal stops at the observer: no new result is produced, so
nothing rebuilds. What it does not narrow is the rest of the result — a widget
is handed a `QueryResult`, and `fetchStatus`, `failureCount` and
`dataUpdatedAt` are part of it. A background refetch that returns identical
data still moves `dataUpdatedAt`, and that is a changed result, so the widget
rebuilds with an unchanged `data`. `select` is the tool for *what a widget
reads*; `buildWhen` below is the tool for *when it rebuilds*, and only the
second one can ignore a metadata change.

Equal by value, for the part `select` does control: a `select` returning a
fresh list every call is fine (lists are shared element by element), and so is
a fresh instance of a class with `==`/`hashCode`. A fresh instance of a class
*without* value equality is a different value every time, so every fetch
reaches the widget as a change. Give such a model `==`, or select a list or a
scalar. Dart records already have value equality, which makes them the easy
pick for a `select` output: `select: (data) => (connected: data.connected,
total: data.total)`.

> Upstream narrows this further than the port does. React Query tracks which
> fields of the result a component actually touched during a render
> (`trackedProps`) and re-renders only when one of those changed. That trick
> needs a proxy around the result and a render pass it can observe; a Flutter
> widget reads its result in `build` with no such seam, so this port compares
> whole results instead and rebuilds where upstream sometimes would not.
> `buildWhen` is the explicit form of the same thing.

`buildWhen`, on every builder (`QueryBuilder`, `QuerySelectBuilder`,
`InfiniteQueryBuilder`, `MutationBuilder`), skips the rest:

```dart
QueryBuilder<Sensor>(
  options: sensorQuery(id),
  buildWhen: (previous, current) => previous.dataOrNull != current.dataOrNull,
  builder: (context, result) => …,
)
```

It is upstream's `notifyOnChangeProps`, expressed as a function of the two
results. `previous` is the result the builder last *built*, not the last one
it saw — a result `buildWhen` skipped is not remembered, so the next
comparison is against what is actually on screen. That is the documented
semantics of the field, and it is the opposite of `bloc`'s `buildWhen`, where
`previous` is the last state emitted whether or not it was built. The other
three styles have no equivalent: with them, `select` is the tool.

## Setting up

```dart
final client = QueryClient();

runApp(
  QueryClientProvider(
    client: client,
    child: const MyApp(),
  ),
);
```

`QueryClientProvider.of(context)` finds the client and subscribes the widget to
a provider change, `read` finds it without subscribing (for handlers), and
`maybeOf` returns `null` instead of throwing where a widget can do without one.
The provider does not dispose the client: a `QueryClient` outlives the tree, so
`client.clear()` is yours to call — at the end of a widget test, on a sign-out,
before a hot restart swaps the app. **`mount()`/`unmount()` are not.** The
provider mounts the client it is given and unmounts it again when it goes, and
that count is what keeps focus and reconnect refetches wired; an extra
`unmount()` of your own unbalances it and the client stops listening to either.
Call `unmount()` only to balance a `mount()` you made yourself.

`QueryClientProvider.create` is the other half of that trade: it builds the
client itself and `clear()`s it once the tree comes down, which is what an app
with a single root client usually wants. A rebuild with a different callback
keeps the client; give the widget a new `key` to replace it.

```dart
QueryClientProvider.create(
  create: QueryClient.new,
  child: const MyApp(),
);
```

That does three things while it is mounted:

- **App lifecycle → focus.** Every lifecycle state the app reports is mapped
  onto the client's focus state — `resumed` and `inactive` are focused,
  `hidden`, `paused` and `detached` are not — so `refetchOnWindowFocus` works.
  `inactive` counts as focused on purpose: on iOS it fires for the notification
  shade and every system dialog, and treating those as "unfocused" would
  refetch the world on the way back.
- **A build-aware scheduler.** Results are delivered right away outside a
  build — a tap handler or a resolved future is where Flutter expects a
  `setState`, and one `pump` in a test shows the new result — and after the
  build when they arrive inside one, so a query resolving during a build can
  never call `setState` into it. That covers the frame's build phase and the
  app's very first build, which `runApp` runs outside any frame.
- **Connectivity, only if you bring it.** See below.

## Connectivity

Nothing is installed by default; the client assumes it is online, which is what
upstream does with no listener, and a fetch that cannot reach the network simply
fails and retries. If you want link-state awareness, pass a stream — six lines
with `connectivity_plus`, which stays *your* dependency:

```dart
// Built once — a stream built in `build` would be a new one on every rebuild,
// and the provider would resubscribe each time.
final onlineStatus = Connectivity()
    .onConnectivityChanged
    .map((results) => !results.contains(ConnectivityResult.none));

QueryClientProvider(
  client: client,
  onlineStatus: onlineStatus,
  child: const MyApp(),
)
```

Any `Stream<bool>` will do, single-subscription included: the provider
subscribes once, and a swapped client inherits the last value the stream
reported. The stream reports changes; the state the device is already in comes from
`Connectivity().checkConnectivity()`, which you can feed to
`client.onlineManager.setOnline` once at startup. Worth knowing:
`connectivity_plus` reports a *link*, not reachability. A phone on hotel wifi
with a captive portal reports "connected".

## Signals, hooks and other reactive packages

Not dependencies here, and not planned as such. Because a controller is a
`ValueListenable`, a signals package reads it with whatever it offers for
listenables — `signals_flutter` has `valueListenableToSignal`, for one:

```dart
final sensor = QueryController.create(client, sensorQuery(id));
final signal = valueListenableToSignal(sensor);        // signals_flutter
final connected = computed(() => signal.value.dataOrNull?.connected ?? false);
```

Nothing is needed from this package for that.

## Writing widget tests

A `QueryClient` outlives the widget tree by design — it owns the cache and its
`gcTime` timers. Flutter's test binding asserts that no timer is pending when
the tree comes down, and it checks that **before** any `tearDown` runs, so the
cleanup has to happen inside the test body. `package:tanstack_query_flutter/testing.dart`
does it for you:

```dart
import 'package:tanstack_query_flutter/testing.dart';

queryWidgetTest('the list loads', (tester, client) async {
  await tester.pumpWidget(app(client, const SensorScreen()));
  await tester.pumpAndSettle();
  expect(find.text('Sensor a'), findsOneWidget);
});
```

The client is built for the case and taken down after it; pass `createClient`
to give it `defaultOptions`. For a test that builds its own clients, or drives
more than one, `tearDownQueryClient(tester, client)` is the same three steps on
their own:

```dart
await tester.pumpWidget(const SizedBox()); // let the widgets go
await tester.pumpAndSettle();              // and the frame after them run
client.clear();                            // then the cache and its timers
```

Import that library from `test/` only — it pulls in `flutter_test`.

## Licence

MIT. Upstream's MIT notice is kept in `LICENSE-TANSTACK`.
