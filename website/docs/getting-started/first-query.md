---
title: Your first query
sidebar_position: 2
description: A provider at the root, an options function, a widget that reads it — and the mutation that invalidates it.
---

# Your first query

Three pieces: a client at the root of the app, a function that describes the
query, and a widget that reads it.

## 1. A client at the root

```dart
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

```dart
QueryClientProvider.create(
  create: QueryClient.new,
  child: const MyApp(),
);
```

## 2. Describe the query once

Put the options behind a function. Nothing forces this, but it is what makes
the same query readable from several widgets without drift:

```dart
final tasksKey = QueryKey(<Object?>['tasks']);

QueryObserverOptions<List<Task>> tasksQuery() =>
    QueryObserverOptions(
      queryKey: tasksKey,
      queryFn: (context) => api.listTasks(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );
```

Four things are worth noticing here.

**The one type argument is the data type.** It comes from `queryFn`'s return
type, or is written out as here — `QueryObserverOptions<List<Task>>`. A query
whose widgets see a projection of the data is the other shape,
`QuerySelectOptions<TQueryData, TData>`, with `select` required; see
[options](../guides/options.md#two-shapes). The one literal neither shape can
type is a key-only one with neither a `queryFn` nor a type argument. The
binding's controllers refuse that in debug builds with a message naming the
cure, and the analyzer reports it at the literal once your
`analysis_options.yaml` asks it to — recommended:

```yaml
analyzer:
  language:
    strict-inference: true
```

**`QueryKey` is a value type**, deep-frozen with structural equality — not a
hashed string. Two keys built from equal contents *are* the same key.

**`context.signal` is a `QueryCancelToken`.** Dart has no ecosystem-wide
cancellation primitive, so `signal.onCancel(…)` is the interop point — hand it
`dio`'s `CancelToken.cancel`, or ignore it entirely with a client that cannot
cancel. See [cancellation](../guides/the-query-client.md#cancellation).

**`StaleTime.duration(…)` rather than a number.** Every option that has a real
"off" value is a sealed value type, so `null` can mean "not configured" on
every field. [Options](../guides/options.md) has the full set.

## 3. Read it

```dart
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
            children: [for (final task in data) TaskTile(task)],
          ),
      },
    );
  }
}
```

`QueryResult` is sealed, so the `switch` is exhaustive and there is no `data!`
anywhere. `QueryError` also carries `staleData` — the last good value — which
is what lets an error banner sit *above* the data that is still on screen
rather than replacing it.

This is one of [four equal ways to read a query](../guides/reading-a-query.md).
The other three are a builder widget, a `State` mixin and a plain
`ValueListenable`; none of them is the default.

## 4. Write something, and invalidate

```dart
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
`add.mutate(vars)` starts it.

`MutationOptions.simple` is the form without an `onMutate` step; it fixes the
rollback type to `void` so the other two infer from `mutationFn`. The full
story, including optimistic updates and rollback, is in
[mutations](../guides/mutations.md).

## What you just got

Without writing any of it:

- **One request for N readers.** Mount the same query in five widgets and the
  cache deduplicates it.
- **Stale-while-revalidate.** A second visit renders from cache immediately and
  refetches behind it if the data is older than `staleTime`.
- **Refetch on focus and on reconnect**, retries with exponential backoff, and
  garbage collection of entries nobody is watching.
- **Cancellation** the moment nothing is observing the query any more.

Which of those fire, and when, is [options](../guides/options.md).

## A runnable version

`packages/query_kit_flutter/example/` is a one-file tour of the same ground —
a provider, a query read three ways and a mutation that invalidates it, with
no server. `flutter run` in that directory.

For the full catalogue, every feature as its own screen against a real
backend, see [the examples](../project/examples.md).
