---
title: Reading a query
sidebar_position: 1
description: Four equal call styles — context.query, QueryBuilder, QueryMixin, QueryController — and how to pick between them.
---

# Reading a query

`useQuery` has no single counterpart here. The binding offers **four equal
ways** to read a query, and **the documentation names no default**: this was
the maintainer's explicit ruling, and it holds for everything built on top.

They are layered, not competing — each is a thin shell over the one below —
and they interoperate inside one screen. The
[`four-call-styles` example screen](../project/examples.md) puts all four on
one key and shows that five readers still cost one request.

## `context.query(...)`

```dart
class TaskScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final task = context.query(taskQuery(id));
    return switch (task) {
      QueryPending() => const CircularProgressIndicator(),
      QuerySuccess(:final data) => TaskCard(data),
      QueryError(:final error, :final staleData) => ErrorBanner(error, staleData),
    };
  }
}
```

Flat, works in a `StatelessWidget`, and **rebuilds only the widgets that read
that query** — a change to one query does not touch the rest of the screen. It
also has the most machinery behind the curtain.

Things to know:

- **Read in `build`, not in a handler.** The read is reconciled against the
  previous build; that is how an unused key is released.
- Each reading widget gets observers of its own. What is shared is the query in
  the cache, which the core deduplicates.
- A widget that stops calling `context.query` *altogether* gives no signal
  Flutter can see, so its last observers stay until it unmounts. Put a
  conditional read in its own small widget.
- `context.selectQuery` is the form with a `select`; it takes a
  `QuerySelectOptions` (see [options](options.md#two-shapes)).
- `context.query`, `context.selectQuery` and `context.infiniteQuery` take
  [`buildWhen`](rebuilds.md#buildwhen), exactly as the builders do. It is per
  read; a change any read lets through rebuilds the whole widget.
- `context.query` always reads the provider's client and takes no `client:` —
  a `BuildContext` names exactly one provider. For a different client, use a
  builder (`client:`), a controller, or override `queryClient` on a
  `QueryMixin` `State`.

## `QueryBuilder`

```dart
QueryBuilder<Task>(
  options: taskQuery(id),
  builder: (context, result) => switch (result) { /* … */ },
)
```

The `StreamBuilder` shape: the most explicit and the most predictable —
everything is visible in the tree — and the natural fit inside a list or a
sliver. Several queries on one screen means several nested builders.

`QuerySelectBuilder<TQueryData, TData>` is the same widget for a query with a
`select` — a `QuerySelectOptions<TQueryData, TData>`. Builders take
[`buildWhen`](rebuilds.md#buildwhen), and so do the two keyless reads.

## `QueryMixin`

```dart
class _TaskScreenState extends State<TaskScreen> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final task = watchQuery(taskQuery(widget.id));
    final rename = watchMutation(renameTask(widget.id));
    // …
  }
}
```

Flat like `context.query`, but owned by the `State`. Entries are identified by
their `QueryKey` and types, not by call order, so **`watchQuery` inside an `if`
is fine** — there is no equivalent of the rules of hooks. A key read in the
previous build but not in this one is released after the frame.

Two reads of one key with different selectors of the same output type, or two
mutations of the same shape, are told apart by an `id:` argument — and reading
two of them *without* one is caught by an assertion in debug builds.

`watchQuery`, `watchSelectQuery` and `watchInfiniteQuery` also take
[`buildWhen`](rebuilds.md#buildwhen), exactly as the builders do. It is per
read; a change any of them lets through rebuilds the whole `State`, because a
`State` is one reader.

An `id:` is then the read's identity, which matters when the key changes:

```dart
// With an id, the observer follows the key — so keepPrevious has a previous.
final page = watchQuery(pageQuery(widget.page), id: 'page');
```

A read that carries an `id:` keeps its observer when its key changes, the way
upstream's one-observer-per-call-site does, so
`PlaceholderData.compute((previous, _) => previous)` shows the previous key's
data while the next one loads. Without an `id:`, a new key is a new observer
and the placeholder has nothing previous to show.

## `QueryController`

```dart
final task = QueryController.create(client, taskQuery(id));
// … task.value, task.addListener, task.refetch() …
task.dispose();
```

A `ValueListenable<QueryResult<T>>`. Nothing hidden, testable without widgets,
and the foundation the other three stand on. `QueryController<TQueryData,
TData>(client, options)` is the constructor form for a `select` whose output
type differs from the cache's.

Its `value` before the first listener is the **optimistic** result —
`fetching` for a query that will fetch on subscribe — the same thing a widget
sees on its first build. It notifies only when something a reader can see has
moved since the last time it said anything, so a `ValueListenableBuilder` over
one does not rebuild for the fetch its own subscription started.

A controller takes no `buildWhen`, and that is not a fourth exception: a
controller **is** the notifier, and a predicate on it would impose one
listener's filter on every listener. Its equivalent is the guarantee just
named, plus composition — which is what a `ValueListenable` is for.

Because it is a plain listenable, it drops into `ValueListenableBuilder`,
`ListenableBuilder`, `Listenable.merge`, `provider`, `riverpod` and `bloc`
unchanged. See [signals and other reactive
packages](#signals-hooks-and-other-reactive-packages).

## Picking one

There is no right answer, which is why there is no default. What the examples
converged on:

| Situation | What fits |
|---|---|
| A leaf that renders one query | `context.query` — flat, and only that widget rebuilds |
| Inside a `ListView.builder` or a sliver | `QueryBuilder` — the tree stays explicit |
| A `State` that is already stateful (a form, a controller) | `QueryMixin` — the query and its mutations go flat at the top of `build` |
| Two siblings that need the same result | `QueryController` held by the parent |
| You want `buildWhen` | a builder, `watchQuery` or `context.query`; a controller filters in its listener instead |
| No widgets at all | `QueryController`, or the core's `QueryObserver` |

## Signals, hooks and other reactive packages

Not dependencies here, and not planned as such. Because a controller is a
`ValueListenable`, a signals package reads it with whatever it offers for
listenables — `signals_flutter` has `valueListenableToSignal`, for one:

```dart
final task = QueryController.create(client, taskQuery(id));
final signal = valueListenableToSignal(task);        // signals_flutter
final done = computed(() => signal.value.dataOrNull?.done ?? false);
```

Nothing is needed from this package for that.
