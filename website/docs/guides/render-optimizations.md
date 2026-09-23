---
title: What rebuilds, and when
description: select narrows what a widget reads; buildWhen narrows when it rebuilds. They are not the same tool.
---

{/* demo: select-and-sharing, build-when */}

# What rebuilds, and when

The rule is TanStack Query's: **a widget rebuilds whenever its result changes** — and
a background refetch that brings back *equal* data is still a change, because
`dataUpdatedAt` moved.

Two tools narrow that down, and they do different jobs. Reaching for the wrong
one is the most common way to be surprised here.

## `select` narrows what a widget reads

A `select` runs at the observer. A fetch that brings back data whose
*selection* is equal keeps the previous selected value — same instance, so
`data` is unchanged and anything compared on it (a `buildWhen` over
`dataOrNull`, a child keyed on the data) sees no change.

```dart snippet="guides/render-optimizations.md#select"
QuerySelectOptions<List<Task>, int> doneCountQuery() => QuerySelectOptions(
      queryKey: tasksKey,
      queryFn: (context) => api.listTasks(signal: context.signal),
      select: (tasks) => tasks.where((s) => s.done).length,
    );
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

```dart snippet="guides/render-optimizations.md#record-select"
select: (data) => (
  done: data.where((s) => s.done).length,
  total: data.length,
),
```

## `buildWhen`

On every builder — `QueryBuilder`, `QuerySelectBuilder`,
`InfiniteQueryBuilder`, `MutationBuilder` — and on every keyless read:
`watchQuery`, `watchSelectQuery`, `watchInfiniteQuery`, `watchMutation`,
`context.query`, `context.selectQuery`, `context.infiniteQuery`,
`context.mutation`.

```dart snippet="excerpt: guides/render-optimizations.md#build-when-builder"
QueryBuilder<Task>(
  options: taskQuery(id),
  buildWhen: (previous, current) => previous.dataOrNull != current.dataOrNull,
  builder: (context, result) => /* … */,
)
```

```dart snippet="guides/render-optimizations.md#build-when-keyless"
final task = context.query(
  taskQuery(id),
  buildWhen: (previous, current) => previous.dataOrNull != current.dataOrNull,
);
```

It is the counterpart of `notifyOnChangeProps`, expressed as a function of two
results. The same predicate and the same semantics in all twelve places — the
difference is only *whose* rebuild it decides. A builder's
is its own subtree, because a builder reads exactly one query or one mutation.
A keyless read's is per read, and its reader is the whole widget or the whole
`State`: several reads each filter their own query, and a change any one of
them lets through rebuilds the reader.

:::note[`previous` is what was built, not what was seen]
`previous` is the result the reader last **built**, not the last one it saw. A
result `buildWhen` skipped is not remembered, so the next comparison is against
what is actually on screen.

It is the **opposite** of
`bloc`'s `buildWhen`, where `previous` is the last state emitted whether or not
it was built.
:::

An equal result is skipped before the predicate is even asked, so `buildWhen`
only ever sees a real change. The one exception is an infinite query, whose
paging flags live beside the result: a fetch that moves only those rebuilds
regardless, because there is nothing there for a predicate over results to
compare and the reader is showing the stale half.

### On a mutation

The same predicate over a `MutationResult`, and it is the *only* narrowing a
mutation reader has: there is no `select` on a mutation.

```dart snippet="guides/render-optimizations.md#build-when-mutation"
final rename = context.mutation(
  renameTask(id),
  // A retrying run moves `failureCount` while it stays pending; a spinner
  // does not care which attempt it is on.
  buildWhen: (previous, current) => previous.status != current.status,
);
```

It is also asked more often than a query's. A `MutationObserver` drops a
notification whose result is equal before it sends one at all, so every
notification a mutation reader gets reaches its predicate.

### A controller has none, on purpose

No controller takes a `buildWhen` — not `QueryController`,
`InfiniteQueryController` or `MutationController`. A controller **is** the notifier: a
predicate on it would impose one listener's filter on every listener of it. What it gives
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
which. A reader who wants per-query filtering has it already, by reading each query with its own `QueryBuilder` or
`context.query`, each with its own `buildWhen`. It makes the other half of the
guarantee: the collection notifies only when a result in it actually moved,
compared element by element.

## Why not track which fields were read

React Query tracks which fields of the result a component touched during a
render (`trackedProps`) and re-renders only when one of those changed. That
needs a proxy around the result and a render pass it can observe; a Flutter
widget reads its result in `build` with no such seam. So whole results are
compared instead, and a widget rebuilds where React Query sometimes would not.
`buildWhen` is the explicit form of the same thing. See [differences from
TanStack Query](../reference/differences-from-tanstack.md).

## Build-aware delivery

Results are delivered right away outside a build — a tap handler or a
resolved future is where Flutter expects a `setState`, and one `pump` in a
test shows the new result — and **after** the build when they arrive inside
one, so a query resolving during a build can never call `setState` into it.
That covers the frame's build phase and the app's very first build, which
`runApp` runs outside any frame.

## Seeing it

The `select-and-sharing` screen in the [examples](../examples/index.md) puts a build counter next to each
reader and lets you refetch with equal or changed data, so the difference
between "the fetch happened" and "the widget rebuilt" is on screen rather than
in your head.

Its `build-when` screen is this page's other half: each of the eight keyless
reads is made twice over one entry — once with a predicate, once without — so
what the predicate costs and saves is the difference between two counters
rather than a claim. A knob swaps the predicate for `(_, __) => false` and for
`(_, __) => true`, which freezes the filtered half and then makes it its twin
again.

What `select` keeps depends on [structural sharing](structural-sharing.md).
