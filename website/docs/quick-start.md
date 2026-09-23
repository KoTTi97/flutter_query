---
title: Quick start
description: A provider at the root, an options function, a widget that reads it — and the mutation that invalidates it.
---

{/* demo: basic */}

# Quick start

Four pieces: a client at the root of the app, a function that describes the
query, a widget that reads it, and a write that tells the cache what it made
stale.

## 1. A client at the root

```dart snippet="quick-start.md#main"
void main() {
  runApp(
    QueryClientProvider(
      client: QueryClient(),
      child: const MaterialApp(home: TasksScreen()),
    ),
  );
}
```

The provider **mounts** the client it is given, which is what wires up
refetch-on-focus, refetch-on-reconnect and the resuming of paused mutations.
It does *not* dispose it: a `QueryClient` outlives the tree by design, so
`client.clear()` is yours to call — at sign-out, or at the end of a widget test.

If you want the provider to own the client as well, use
`QueryClientProvider.create`, which builds it and `clear()`s it when the tree
comes down:

```dart snippet="quick-start.md#main-owning-its-client"
void main() {
  runApp(
    QueryClientProvider.create(
      create: QueryClient.new,
      child: const MaterialApp(home: TasksScreen()),
    ),
  );
}
```

Create the client once — never in a `build` method, where every rebuild would
start an empty cache.

## 2. Describe the query once

Put the options behind a function. Nothing forces this, but it is what makes
the same query readable from several widgets without drift:

```dart snippet="quick-start.md#key quick-start.md#options"
final QueryKey tasksKey = QueryKey(<Object?>['tasks']);

QueryObserverOptions<List<Task>> tasksQuery() => QueryObserverOptions(
      queryKey: tasksKey,
      queryFn: (context) => api.listTasks(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );
```

- The **key** identifies the data in the cache. `QueryKey` is a value type:
  two keys built from equal parts are the same key. See [query
  keys](guides/query-keys.md).
- The **function** fetches it, and must throw when it fails. `context.signal`
  lets it cancel its request. See [query functions](guides/query-functions.md).
- The **one type argument** is the data type. A query that shows a projection
  of its data uses the other shape, `QuerySelectOptions`. See [describing a
  query once](guides/query-options.md).
- **`StaleTime.duration(…)`** rather than a number: every option with a real
  "off" value is a sealed value type. See [important
  defaults](important-defaults.md).

## 3. Read it

```dart snippet="quick-start.md#screen"
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.query(tasksQuery());

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: switch (tasks) {
        QueryPending() => const Center(child: CircularProgressIndicator()),
        QueryError(:final error) => Center(child: Text('$error')),
        QuerySuccess(:final data) => ListView(
            children: <Widget>[
              for (final task in data) TaskTile(task),
            ],
          ),
      },
    );
  }
}
```

`QueryResult` is sealed, so the `switch` is exhaustive and there is no `data!`
anywhere. `QueryError` also carries `staleData` — the last good value — which
is what lets an error banner sit *above* the data that is still on screen
rather than replacing it. [Queries](guides/queries.md) explains every state a
result can be in.

This is one of [four equal ways to read a
query](guides/reading-queries-in-widgets.md). The other three are a builder
widget, a `State` mixin and a plain `ValueListenable`; none of them is the
default.

## 4. Write something, and invalidate

```dart snippet="quick-start.md#mutation"
@override
Widget build(BuildContext context) {
  // Take the client here, in build — not inside the callback. A mutation
  // outlives the widget that started it, so `onSuccess` can run after this
  // element is gone, and looking an ancestor up from a deactivated element
  // throws.
  final client = QueryClientProvider.of(context);

  final add = context.mutation(
    MutationOptions.simple(
      mutationFn: api.addTask,
      onSuccess: (_, __, ___) => client.invalidateQueries(
        filters: QueryFilters(queryKey: tasksKey),
      ),
    ),
  );

  return FilledButton(
    onPressed: add.value.isPending ? null : () => add.mutate('New task'),
    child: Text(add.value.isPending ? 'Adding…' : 'Add'),
  );
}
```

A mutation hands back a `MutationController` rather than a result, because you
need `mutate` as well as the state: `add.value` is the `MutationResult`,
`add.mutate(vars)` starts it. Invalidating the list marks it stale and
refetches it while it is on screen. See [mutations](guides/mutations.md) and
[invalidation from mutations](guides/invalidations-from-mutations.md).

## What you just got

Without writing any of it:

- **One request for many readers.** Mount the same query in five widgets and
  the cache deduplicates it.
- **Stale-while-revalidate.** A second visit renders from cache immediately and
  refetches behind it if the data is older than `staleTime`.
- **Refetch on focus and on reconnect**, retries with exponential backoff, and
  garbage collection of entries nobody is watching.
- **Cancellation** the moment nothing is observing the query any more, when
  the query function hands `context.signal` to its HTTP client.

Which of those fire, and when, is [important defaults](important-defaults.md).

## A runnable version

The showcase's `simple` screen is this page's query, running in your browser:
one read, its loading and success states, and a refetch that keeps the data on
screen while it runs. The backend is in memory, with the same 300 ms latency
as the real one.

<LiveDemo feature="simple" height={560} />

`packages/query_kit_flutter/example/` is a one-file tour of the same ground —
a provider, a query read two ways and a mutation that invalidates it, with
no server. `flutter run` in that directory.

For every feature as its own screen, see [the examples](examples/index.md).
