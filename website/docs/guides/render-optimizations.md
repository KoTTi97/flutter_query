---
title: What rebuilds, and when
description: select narrows what a widget reads; buildWhen narrows when it rebuilds. They are not the same tool.
---

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

## In an app

A lamp badge on each room tab shows how many lights are on. It reads the
room's device list — the same options the room screen reads, so one request
serves both — selects a count, and rebuilds only when the count moves:

```dart snippet="guides/render-optimizations.md#room-badge"
class RoomBadge extends StatelessWidget {
  const RoomBadge({super.key, required this.room});

  final String room;

  @override
  Widget build(BuildContext context) {
    // Reads the room's list, keeps a count. A device renamed, or a refetch
    // that changes nothing, leaves the count — and this badge — alone.
    final on = context.selectQuery(
      roomDevicesQuery(room).withSelect(_countOn),
      buildWhen: (previous, current) =>
          previous.dataOrNull != current.dataOrNull,
    );
    return Badge(
      label: Text('${on.dataOrNull ?? 0}'),
      child: const Icon(Icons.lightbulb_outline),
    );
  }
}

// Top-level, so the options compare equal from one build to the next.
int _countOn(List<Device> list) => list.where((device) => device.isOn).length;
```

`withSelect` turns the room's plain options into select options without
restating the key and the function. The `select` alone keeps `data` the same
`int` across a rename or a refetch that changes nothing; the `buildWhen` also
ignores the `fetchStatus` and `dataUpdatedAt` that every refetch moves. The
room screen next to it, which shows those names, rebuilds on a rename; the
badge does not.

Pass a top-level function or a static method as `select`, not a closure
written inline: a new closure each build is a new option, and the observer
runs the new `select` again over data it has already selected.

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

The `select-and-sharing` screen reads one entry five times, with a different
`select` each, and counts every reader's builds and its *data builds* — the
builds whose selected value changed. Press *Refetch*: the data comes back
equal, every reader's *data builds* stays put, and only the builder with a
`buildWhen` does not rebuild at all. *Toggle todo 1* changes what some
selections see and not others. Tick *Structural sharing off* and refetch: the
reader without a `select` and the one whose selection is a new list each
time now count a data change for equal data.

<LiveDemo feature="select-and-sharing" />

The `build-when` screen is this page's other half: each of the eight keyless
reads is made twice over one entry — once with a predicate, once without — so
what the predicate costs and saves is the difference between two counters.
Press *Refetch the posts* and watch the unfiltered counters move while the
filtered ones stay; set the *buildWhen* knob to *never* to freeze the filtered
half, and to *always* to make it its twin again.

<LiveDemo feature="build-when" />

What `select` keeps depends on [structural sharing](structural-sharing.md).

:::note[In React Query]
`select` is the same option. `notifyOnChangeProps` and tracked properties
decide there which result fields re-render a component; `buildWhen` is that
decision written as a function of the previous and the current result, on
every builder and every keyless read.
:::
