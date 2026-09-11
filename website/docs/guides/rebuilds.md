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
`InfiniteQueryBuilder`, `MutationBuilder`:

```dart
QueryBuilder<Task>(
  options: taskQuery(id),
  buildWhen: (previous, current) => previous.dataOrNull != current.dataOrNull,
  builder: (context, result) => /* … */,
)
```

It is upstream's `notifyOnChangeProps`, expressed as a function of two results.

:::note `previous` is what was built, not what was seen
`previous` is the result the builder last **built**, not the last one it saw. A
result `buildWhen` skipped is not remembered, so the next comparison is against
what is actually on screen.

That is the documented semantics of the field, and it is the **opposite** of
`bloc`'s `buildWhen`, where `previous` is the last state emitted whether or not
it was built.
:::

The other three call styles have no `buildWhen`. With them, `select` is the
tool.

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
