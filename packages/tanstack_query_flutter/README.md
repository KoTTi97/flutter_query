# tanstack_query_flutter

The Flutter binding for [`tanstack_query_core`](../tanstack_query_core) — a
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
that key** — a change to one query does not touch the rest of the screen. The
most machinery behind the curtain; the observer is shared and reference-counted
across every widget reading the same key.

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
`QueryKey`, not by call order, so `watchQuery` inside an `if` is fine — there is
no equivalent of the rules of hooks.

### `QueryController`

```dart
final sensor = QueryController<Sensor, Sensor>(client, sensorQuery(id));
// … sensor.value, sensor.addListener, sensor.refetch() …
sensor.dispose();
```

A `ValueListenable<QueryResult<T>>`. Nothing hidden, testable without widgets,
and the foundation the other three stand on. Because it is a plain listenable,
it also drops into `ValueListenableBuilder`, `ListenableBuilder`,
`Listenable.merge`, `provider`, `riverpod` and `bloc` unchanged.

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

That does three things while it is mounted:

- **App lifecycle → focus.** `onShow`/`onHide` set the client's focus state, so
  `refetchOnWindowFocus` works. `onInactive` is deliberately ignored: on iOS it
  fires for the notification shade and every system dialog, and treating those
  as "unfocused" would refetch the world on the way back.
- **A build-phase-aware scheduler.** A query that resolves mid-build notifies
  after the frame, so it can never call `setState` during a build.
- **Connectivity, only if you bring it.** See below.

## Connectivity

Nothing is installed by default; the client assumes it is online, which is what
upstream does with no listener, and a fetch that cannot reach the network simply
fails and retries. If you want link-state awareness, pass a stream — six lines
with `connectivity_plus`, which stays *your* dependency:

```dart
QueryClientProvider(
  client: client,
  onlineStatus: Connectivity()
      .onConnectivityChanged
      .map((results) => !results.contains(ConnectivityResult.none)),
  child: const MyApp(),
)
```

Worth knowing: `connectivity_plus` reports a *link*, not reachability. A phone
on hotel wifi with a captive portal reports "connected".

## Signals, hooks and other reactive packages

Not dependencies here, and not planned as such. Because a controller is a
`ValueListenable`, `signals` reads it directly:

```dart
final sensor = QueryController<Sensor, Sensor>(client, sensorQuery(id));
final signal = sensor.toSignal();                      // signals_flutter
final connected = computed(() => signal.value.dataOrNull?.connected ?? false);
```

`signals_flutter` ships `valueListenableToSignal`, `ValueListenableSignalMixin`
and friends, so nothing is needed from this package.

## Writing widget tests

A `QueryClient` outlives the widget tree by design — it owns the cache and its
`gcTime` timers. Flutter's test binding asserts that no timer is pending when
the tree comes down, and it checks that **before** any `tearDown` runs, so the
cleanup has to happen inside the test body:

```dart
testWidgets('…', (tester) async {
  await tester.pumpWidget(app(client, const SensorScreen()));
  // … assertions …

  await tester.pumpWidget(const SizedBox()); // let the widgets go
  client.clear();                            // and the cache with them
});
```

`test/binding_test.dart` wraps that in a small `widgetTest` helper worth copying.

## Licence

MIT. Upstream's MIT notice is kept in `LICENSE-TANSTACK`.
