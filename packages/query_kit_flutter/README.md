# query_kit_flutter

TanStack Query for Flutter: cached server state with background refetching,
retries, mutations and infinite queries, read from your widgets in whichever
of four equal styles suits the screen. **No dependency beyond Flutter** — not
`flutter_hooks`, not a signals package, not `connectivity_plus`.

> **AI-coded.** query_kit is an entirely AI-coded project: all code, tests
> and documentation were written by AI coding agents (Anthropic's Claude). A
> human maintainer set the goals and reviews releases, but did not write the
> code.
>
> **A port, not affiliated.** The behaviour is
> [TanStack Query](https://tanstack.com/query)'s, and upstream's own test
> suite is ported case by case — every case left out is listed with its
> reason — and run against the core, with thanks to Tanner Linsley and the
> TanStack team. This package is not affiliated with,
> endorsed by or connected to them; please take problems to
> [this repository's issues](https://github.com/dualmeta-gmbh/query_kit/issues),
> not to TanStack.

## Install

```bash
flutter pub add query_kit_flutter
```

That brings [`query_kit`](https://pub.dev/packages/query_kit), the core, with
it, and one import is enough — the binding re-exports the core:

```dart snippet="prose-only: the one import line, which every other sample already shows in context"
import 'package:query_kit_flutter/query_kit_flutter.dart';
```

Requires Flutter 3.27 or later.

## Quick start

### 1. Provide a client

One `QueryClient`, created once and placed above everything that reads it:

```dart snippet="packages/query_kit_flutter/README.md#setup"
final client = QueryClient();

runApp(
  QueryClientProvider(
    client: client,
    child: const MyApp(),
  ),
);
```

The provider wires the app lifecycle to the client, so queries refetch when
the app comes back to the foreground. It does not dispose the client; use
`QueryClientProvider.create(create: QueryClient.new, child: …)` if the
provider should own it.

### 2. Describe a query and read it

A query is a key plus a function that fetches. Describe it once:

```dart snippet="packages/query_kit_flutter/README.md#query-options"
QueryObserverOptions<List<Task>> tasksQuery() => QueryObserverOptions(
      queryKey: QueryKey(<Object?>['tasks']),
      queryFn: (context) => api.listTasks(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );
```

and read it from a widget:

```dart snippet="packages/query_kit_flutter/README.md#first-query"
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.query(tasksQuery());

    return switch (tasks) {
      QueryPending() => const Center(child: CircularProgressIndicator()),
      QueryError(:final error) => Center(child: Text('$error')),
      QuerySuccess(:final data) => ListView(
          children: [for (final task in data) Text(task.name)],
        ),
    };
  }
}
```

The result is a **sealed** type, so the `switch` is exhaustive and the data
needs no `!`. Every widget reading `tasksQuery()` shares one cache entry and
one request.

`context.query` is one of **four equal ways** to read a query. None is the
recommended default; they interoperate on one screen, so pick per situation:

```dart snippet="excerpt: packages/query_kit_flutter/README.md#builder"
// A builder widget, the StreamBuilder shape.
QueryBuilder<List<Task>>(
  options: tasksQuery(),
  builder: (context, result) => switch (result) { … },
)
```

```dart snippet="excerpt: packages/query_kit_flutter/README.md#mixin"
// A mixin on a State.
class _TasksPageState extends State<TasksPage> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final tasks = watchQuery(tasksQuery());
    …
  }
}
```

```dart snippet="packages/query_kit_flutter/README.md#controller"
final tasks = QueryController.create(client, tasksQuery());
// … tasks.value, tasks.addListener, tasks.refetch() …
tasks.dispose();
```

A `QueryController` is a `ValueListenable<QueryResult<T>>`, so it also works
with `ValueListenableBuilder` and with any state-management package that can
listen to a `Listenable`.

### 3. A first mutation

A mutation changes something on the server; invalidating the list afterwards
refetches it for every widget that reads it:

```dart snippet="packages/query_kit_flutter/README.md#first-mutation"
@override
Widget build(BuildContext context) {
  // Take the client in build, not in the callback: a mutation can outlive
  // the widget that started it.
  final client = QueryClientProvider.of(context);

  final add = context.mutation(
    MutationOptions.simple(
      mutationFn: api.addTask,
      // Mark the list stale; everyone reading it refetches.
      onSuccess: (_, __, ___) => client.invalidateQueries(
        filters: QueryFilters(queryKey: QueryKey(<Object?>['tasks'])),
      ),
    ),
  );

  return FilledButton(
    onPressed: add.value.isPending ? null : () => add.mutate('New task'),
    child: Text(add.value.isPending ? 'Adding…' : 'Add'),
  );
}
```

Mutations come in the same four styles: `context.mutation`, `watchMutation`,
`MutationBuilder` and `MutationController`.

## Features

- **Four equal call styles** for queries, infinite queries and mutations:
  `context.query`, `QueryBuilder`, `QueryMixin` and `QueryController`.
- **Precise rebuilds.** A widget rebuilds when its result changes; `select`
  narrows the data it sees and `buildWhen` decides when it rebuilds.
- **Everything from the core**: caching with `staleTime` and `gcTime`,
  request deduplication, retries with backoff, cancellation, optimistic
  updates with rollback, `MutationScope`, infinite queries with `maxPages`,
  initial and placeholder data, structural sharing.
- **App lifecycle as focus**: coming back to the foreground refetches stale
  queries, with the `inactive` state read per platform.
- **Connectivity you bring**: pass an `OnlineStatus` built from
  `connectivity_plus` or anything else; nothing is installed by default.
- **Side effects off the build phase**: `QueryListener`, `InfiniteQueryListener`
  and `MutationListener` for snackbars and navigation.
- **Lists and combinations**: `QueriesBuilder` / `QueriesController` for a
  dynamic list of queries, and `(a, b).combine(…)` for results of different
  types.
- **App-wide indicators**: `IsFetchingController` for a global loading bar,
  `MutationStateController` for a "saving…" badge.
- **Testable without magic**: controllers work without widgets, and widget
  tests need only a short, documented teardown.

## Connectivity

Nothing listens to the network by default. Pass an `OnlineStatus` and the
client follows it — here with `connectivity_plus`, which stays your
dependency:

```dart snippet="prose-only: needs connectivity_plus, which neither published package may depend on"
// Built once: a stream built in `build` would be resubscribed on every rebuild.
final connectivity = Connectivity()
    .onConnectivityChanged
    .map((results) => !results.contains(ConnectivityResult.none));

QueryClientProvider(
  client: client,
  onlineStatus: OnlineStatus.stream(connectivity, initial: online),
  child: const MyApp(),
)
```

`initial` is required because a stream has no current value; answer it at
startup with `Connectivity().checkConnectivity()`. Use a broadcast stream.
`connectivity_plus` reports a *link*, not reachability: a captive-portal
wifi counts as connected.

## Widget tests

A `QueryClient` outlives the widget tree and owns timers, and Flutter's test
binding checks for pending timers *before* `tearDown` runs. So a widget test
ends by taking the tree down and clearing the client:

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

The [testing guide](https://dualmeta-gmbh.github.io/query_kit/docs/guides/testing)
wraps these steps once per suite.

## Learn more

- [Overview](https://dualmeta-gmbh.github.io/query_kit/docs/overview),
  [quick start](https://dualmeta-gmbh.github.io/query_kit/docs/quick-start) and
  [important defaults](https://dualmeta-gmbh.github.io/query_kit/docs/important-defaults)
- [Four ways to read a query](https://dualmeta-gmbh.github.io/query_kit/docs/guides/reading-queries-in-widgets)
  and [what rebuilds, and when](https://dualmeta-gmbh.github.io/query_kit/docs/guides/render-optimizations)
- [Mutations](https://dualmeta-gmbh.github.io/query_kit/docs/guides/mutations),
  [optimistic updates](https://dualmeta-gmbh.github.io/query_kit/docs/guides/optimistic-updates)
  and [infinite queries](https://dualmeta-gmbh.github.io/query_kit/docs/guides/infinite-queries)
- [App focus](https://dualmeta-gmbh.github.io/query_kit/docs/guides/window-focus-refetching)
  and [connectivity](https://dualmeta-gmbh.github.io/query_kit/docs/guides/connectivity)
- [Testing](https://dualmeta-gmbh.github.io/query_kit/docs/guides/testing)
- [Coming from React Query](https://dualmeta-gmbh.github.io/query_kit/docs/coming-from-react-query)
  and [troubleshooting](https://dualmeta-gmbh.github.io/query_kit/docs/reference/troubleshooting)
- [API reference](https://pub.dev/documentation/query_kit_flutter/latest/)
- A runnable one-file tour: [`example/lib/main.dart`](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit_flutter/example/lib/main.dart)

## License and credits

MIT. query_kit is a port of [TanStack Query](https://tanstack.com/query) by
Tanner Linsley and contributors, whose MIT notice is kept in
`LICENSE-TANSTACK`. Bugs and questions go to
[the issue tracker](https://github.com/dualmeta-gmbh/query_kit/issues).
