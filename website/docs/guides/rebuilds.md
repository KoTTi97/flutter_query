---
title: What rebuilds, and when
sidebar_position: 3
description: select narrows what a widget reads; buildWhen narrows when it rebuilds. They are not the same tool.
---

# What rebuilds, and when

The rule is upstream's: **a widget rebuilds whenever its result changes** — and
a background refetch that brings back *equal* data is still a change, because
`dataUpdatedAt` moved.

Two tools narrow that down, and they do different jobs. Reaching for the wrong
one is the most common way to be surprised here.

## `select` narrows what a widget reads

A `select` runs at the observer. A fetch that brings back data whose
*selection* is equal keeps the previous selected value — same instance, so
`data` is unchanged and anything compared on it (a `buildWhen` over
`dataOrNull`, a child keyed on the data) sees no change.

```dart
QuerySelectOptions<List<Task>, int>(
  queryKey: tasksKey,
  queryFn: (context) => api.listTasks(signal: context.signal),
  select: (tasks) => tasks.where((s) => s.done).length,
)
```

What `select` does **not** narrow is the rest of the result. A widget is handed
a `QueryResult`, and `fetchStatus`, `failureCount` and `dataUpdatedAt` are part
of it — and of its `==`. A background refetch that returns identical data
still moves `dataUpdatedAt` (and `fetchStatus` through `fetching` and back),
and that is a changed result — so the widget **does** rebuild, with an
unchanged `data`. If you want no rebuild at all, `buildWhen` is the tool.

`select` is the tool for *what a widget reads*. `buildWhen` is the tool for
*when it rebuilds*, and only the second one can ignore a metadata change.

### Equal by value

For the part `select` does control, equality is `==`:

- a `select` returning a **fresh list** every call is fine — lists are shared
  element by element;
- a fresh instance of a class **with** `==`/`hashCode` is fine;
- a fresh instance of a class **without** value equality is a different value
  every time, so every fetch reaches the widget as a change.

Give such a model `==`, or select a list or a scalar. Dart **records** already
have value equality, which makes them the easy pick:

```dart
select: (data) => (
  done: data.where((s) => s.done).length,
  total: data.length,
),
```

## `buildWhen`

On every builder — `QueryBuilder`, `QuerySelectBuilder`,
`InfiniteQueryBuilder`, `MutationBuilder` — and on the two keyless reads:
`watchQuery`, `watchSelectQuery`, `watchInfiniteQuery`, `context.query`,
`context.selectQuery`, `context.infiniteQuery`.

```dart
QueryBuilder<Task>(
  options: taskQuery(id),
  buildWhen: (previous, current) => previous.dataOrNull != current.dataOrNull,
  builder: (context, result) => /* … */,
)
```

```dart
final task = context.query(
  taskQuery(id),
  buildWhen: (previous, current) => previous.dataOrNull != current.dataOrNull,
);
```

It is upstream's `notifyOnChangeProps`, expressed as a function of two results.
The same predicate, the same semantics and the same implementation in all six
places — the difference is only *whose* rebuild it decides. A builder's is its
own subtree, because a builder reads exactly one query. A keyless read's is
per read, and its reader is the whole widget or the whole `State`: several
reads each filter their own query, and a change any one of them lets through
rebuilds the reader.

:::note `previous` is what was built, not what was seen
`previous` is the result the reader last **built**, not the last one it saw. A
result `buildWhen` skipped is not remembered, so the next comparison is against
what is actually on screen.

That is the documented semantics of the field, and it is the **opposite** of
`bloc`'s `buildWhen`, where `previous` is the last state emitted whether or not
it was built.
:::

An equal result is skipped before the predicate is even asked, so `buildWhen`
only ever sees a real change. The one exception is an infinite query, whose
paging flags live beside the result: a fetch that moves only those rebuilds
regardless, because there is nothing there for a predicate over results to
compare and the reader is showing the stale half.

### A controller has none, on purpose

`QueryController` takes no `buildWhen`, and that is not a fourth exception to
the four styles being equal. A controller **is** the notifier: a predicate on
it would impose one listener's filter on every listener of it. What it gives
instead is the guarantee underneath — it notifies only when something a reader
can see has actually moved, so a `ValueListenableBuilder` over one never
rebuilds for a notification carrying what it is already showing, not even for
the fetch its own subscription started. Past that, a controller is a
`ValueListenable`, so filtering is composition: hold the last value your
listener acted on and compare, or wrap it in whatever your state-management
package offers for a listenable.

### `QueriesBuilder` has none either

A collection has no one result to filter on: a predicate over a whole
`List<QueryResult>` would fire for any query in the list and say nothing about
which. `QueriesBuilder` is not one of the four call styles and has no keyless
twin, so there is no inequality to close — and a reader who wants per-query
filtering has it already, by reading each query with its own `QueryBuilder` or
`context.query`, each with its own `buildWhen`. It makes the other half of the
guarantee: the collection notifies only when a result in it actually moved,
compared element by element.

## Why not upstream's trick

Upstream narrows this further than the port does. React Query tracks which
fields of the result a component actually touched during a render
(`trackedProps`) and re-renders only when one of those changed.

That trick needs a proxy around the result and a render pass it can observe. A
Flutter widget reads its result in `build` with no such seam, so this port
compares whole results instead, and rebuilds where upstream sometimes would
not. `buildWhen` is the explicit form of the same thing.

This is one of the recorded divergences; the reasoning is in the divergence
table at the end of
[`PORTING_NOTES.md`](https://github.com/KoTTi97/flutter_query/blob/main/packages/query_kit/test/PORTING_NOTES.md).

## Seeing it

The showcase's `select-and-sharing` screen puts a build counter next to each
reader and lets you refetch with equal or changed data, so the difference
between "the fetch happened" and "the widget rebuilt" is on screen rather than
in your head.
