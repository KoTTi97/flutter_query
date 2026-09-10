---
title: Collections and side effects
sidebar_position: 7
description: QueriesBuilder for a list of queries, the listener widgets for side effects, and MutationStateController for cache-wide write state.
---

# Collections and side effects

Three widgets sit beside the [four call styles](reading-a-query.md) rather than
among them, because none of them is a way of *reading* one query.

## A list of queries

`QueriesBuilder` observes a list that may change length or order — upstream's
`useQueries`, minus the heterogeneous tuple.

```dart
QueriesBuilder<Task, String>(
  queries: [
    for (final id in visibleIds)
      QueryObserverOptions<Task, String>(
        queryKey: QueryKey(<Object?>['tasks', id]),
        queryFn: (context) => api.getTask(id, signal: context.signal),
        select: (task) => task.name,
      ),
  ],
  builder: (context, results) => Column(children: [
    for (final result in results) Text(result.dataOrNull ?? '…'),
  ]),
)
```

- **Observers are reused by key and occurrence**, so reordering the list starts
  no requests.
- **Duplicate keys** share one cache entry while keeping their own options.
- **Each query fails and settles on its own**; one error does not disturb its
  neighbours.

It is homogeneous: one data type per collection. Mixed data types need a
`select` to a common type, and the returned list is mapped by the caller —
there is no `combine` step. `QueriesObserver` is the same thing without
Flutter.

## Side effects

`QueryListener`, `InfiniteQueryListener` and `MutationListener` run a callback
on a controller they **borrow** — the owner still disposes it — and never
rebuild their `child`.

```dart
QueryListener<Task, Task>(
  controller: task,
  listenWhen: (previous, next) => previous.errorOrNull != next.errorOrNull,
  listener: (context, result) => ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Task unreachable'))),
  child: const TaskTile(),
)
```

Two properties make these safe for navigation and snackbars, which is the whole
point of having them:

- **Nothing fires on mount** — only later transitions.
- **Callbacks are delivered off the build phase**, so a result that arrives
  mid-build reaches the listener after the frame.

A rejected `listenWhen` still advances the comparison state, so the next
callback sees the transition it actually followed. (That is the opposite of
`buildWhen`, where `previous` is what was last *built* — the two fields have
genuinely different jobs.)

## Cache-wide mutation state

`MutationStateController` reads every mutation matching a filter through a
`select` — upstream's `useMutationState`:

```dart
final saving = MutationStateController<int>(
  client,
  filters: const MutationFilters(status: MutationStatus.pending),
  select: (mutation) => 1,
);
// saving.value.length is "how many writes are in flight"
```

That is how a "saving…" badge in an app bar works without any widget owning the
mutation. Concurrent runs under one key are kept apart.

`MutationStateObserver` is the Flutter-free version.

## On screen

`query-collections` (a list that grows, shrinks and reorders, with duplicate
keys and a partial failure), `mutation-state` and `global-callbacks` in the
[showcase](../project/examples.md).
