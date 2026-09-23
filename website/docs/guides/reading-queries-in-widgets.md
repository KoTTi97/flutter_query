---
title: Four ways to read a query
description: context.query, QueryBuilder, QueryMixin and QueryController — four equal call styles, how to pick between them, and when a read is released.
---

# Four ways to read a query

`useQuery` has no single counterpart here. The binding offers **four equal
ways** to read a query, and **the documentation names no default**.

They are layered, not competing — each is a thin shell over the one below —
and they interoperate inside one screen. The showcase's *four call styles*
screen puts them all on one key. Under its first card, *One entry, five
readers*, the strip reads `observers=5` and `fetches=1`: press *Refetch* and
every reader moves
together on one request. Further down, *6. QueryListener, a side effect* counts
`listener-calls` as you press *Drop a post*:

<LiveDemo feature="four-call-styles" height={720} />

Two rules hold for all of them:

- **Read in `build`.** A read is reconciled against the previous build; that
  is how a key you stopped reading is released.
- **One widget per list row or dialog.** A row or a dialog that shows a query
  reads it in its own widget's `build`, so its reads come and go with it.

The details are under [how reads are released](#how-reads-are-released).

## `context.query(...)`

```dart snippet="excerpt: guides/reading-queries-in-widgets.md#context-query"
class TaskScreen extends StatelessWidget {
  // … the id and its constructor …
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
that query** — a change to one query does not touch the rest of the screen.

- `context.selectQuery` is the form with a `select`; it takes a
  `QuerySelectOptions` (see [describing a query once](query-options.md)).
- `context.query`, `context.selectQuery`, `context.infiniteQuery` and
  `context.mutation` take [`buildWhen`](render-optimizations.md#buildwhen),
  exactly as the builders do. It is per read; a change any read lets through
  rebuilds the whole widget.
- Each reading widget gets observers of its own. What is shared is the query
  in the cache, which the core deduplicates.
- `context.query` always reads the provider's client and takes no `client:` —
  a `BuildContext` names exactly one provider. For a different client, use a
  builder (`client:`), a controller, or override `queryClient` on a
  `QueryMixin` `State`.

## `QueryBuilder`

```dart snippet="excerpt: guides/reading-queries-in-widgets.md#builder"
QueryBuilder<Task>(
  options: taskQuery(id),
  builder: (context, result) => switch (result) { /* … */ },
)
```

The `StreamBuilder` shape: the read is a widget in the tree, and a change
rebuilds that widget's subtree. Being a widget, it is also a row of its own
when an `itemBuilder` returns one. Several queries on one screen means
several nested builders.

`QuerySelectBuilder<TQueryData, TData>` is the same widget for a query with a
`select` — a `QuerySelectOptions<TQueryData, TData>`. Builders take
[`buildWhen`](render-optimizations.md#buildwhen).

## `QueryMixin`

```dart snippet="excerpt: guides/reading-queries-in-widgets.md#mixin"
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

`watchQuery`, `watchSelectQuery`, `watchInfiniteQuery` and `watchMutation`
also take [`buildWhen`](render-optimizations.md#buildwhen). It is per read; a
change any of them lets through rebuilds the whole `State`, because a `State`
is one reader.

An `id:` is then the read's identity, which matters when the key changes:

```dart snippet="guides/reading-queries-in-widgets.md#switched-key"
// With an id, the observer follows the key — so keepPrevious has a previous.
final page = watchQuery(pageQuery(widget.page), id: 'page');
```

A read that carries an `id:` keeps its observer when its key changes, so
`PlaceholderData.keepPrevious()` shows the previous key's data while the next
one loads. Without an `id:`, a new key is a new observer and the placeholder
has nothing previous to show. See [paginated queries](paginated-queries.md).

## `QueryController`

```dart snippet="guides/reading-queries-in-widgets.md#controller"
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

A controller takes no `buildWhen`: it **is** the notifier, and a predicate on
it would impose one listener's filter on every listener. Filter in your
listener instead.

Because it is a plain listenable, it drops into `ValueListenableBuilder`,
`ListenableBuilder`, `Listenable.merge`, `provider`, `riverpod` and `bloc`
unchanged. See [does this replace state
management?](does-this-replace-state-management.md) and [signals and other
reactive packages](#signals-hooks-and-other-reactive-packages).

## Picking one

There is no right answer, which is why there is no default. What the examples
converged on:

| Situation | What fits |
|---|---|
| A leaf that renders one query | `context.query` — flat, and only that widget rebuilds |
| Inside a `ListView.builder` or a sliver | a widget per row that reads its own query — a `QueryBuilder`, or a small row widget reading with `context.query` or `watchQuery` in its own `build` — so each row's reads go with it. Not a read through the `itemBuilder`'s own `context` (see [lazily built lists](#how-reads-are-released)) |
| A `State` that is already stateful (a form, a controller) | `QueryMixin` — the query and its mutations go flat at the top of `build` |
| Two siblings that need the same result | `QueryController` held by the parent |
| You want `buildWhen` | a builder, `watchQuery` or `context.query`; a controller filters in its listener instead |
| No widgets at all | `QueryController`, or the core's `QueryObserver` |

## How reads are released

`context.query` and the mixin keep a subscription alive for as long as a build
reads it. Most of the time that needs no thought; these are the cases where
it does.

- **A widget that stops calling `context.query` altogether** gives no signal
  Flutter can see, so its last observers stay until it unmounts. Put a
  conditional read in its own small widget.
- **Nested builder callbacks.** A read through the outer `context` inside a
  `ValueListenableBuilder`, an `AnimatedBuilder` or a `LayoutBuilder` is
  *added* to the enclosing widget's reads and does not release what its own
  `build` read. A key such a callback stops reading is released on that
  widget's next own build that reads, or when it goes — so read in `build`
  itself: a `build` that leaves every read to a nested builder never starts
  over.
- **A `LayoutBuilder`'s or `OrientationBuilder`'s own `context`.** A read
  through it starts over when its builder provably runs: new constraints (the
  wide layout's key goes after a resize), a notification from one of its own
  reads, or a new widget from its parent. One rebuild carries no signal — an
  `InheritedWidget` the builder depends on changing — and a key picked from an
  inherited value stays subscribed until the next of those. **A key that
  depends on anything the builder reads belongs in a widget of its own below
  the `LayoutBuilder`**: `LayoutBuilder(builder: (_, c) => c.maxWidth > 600 ?
  const WideTasks() : const NarrowTasks())`, each reading in its own `build`.
- **Dialogs and bottom sheets.** A read rebuilds the element whose `context`
  it went through. A dialog reading through the page's `context` is not
  rebuilt by a change, and its key goes at the page's next build. Give a
  dialog a reader of its own: read through the `context` the dialog builder is
  given.
- **Lazily built lists.** A `ListView.builder`, `GridView.builder`,
  `PageView.builder` or any other lazily built list hands its item builder the
  whole list's context, not the row's, and builds rows piecemeal as they
  scroll in, so no rule for it both keeps the rows on screen subscribed and
  lets go of the ones scrolled away. A `context.query` (or any other
  `context.` read) through that item-builder `context` is refused: a debug
  build throws a `FlutterError` naming the fix. (In a release build such a
  read is additive: no row on screen loses its subscription, and the rows
  scrolled away stay subscribed until the list is rebuilt or goes.) A
  `watchQuery` inside the `itemBuilder` does not throw — it reads for the
  `State` around the list, additively, as a nested builder does — so the
  rows scrolled away stay subscribed until that `State`'s next own `build`
  that reads, or its disposal. The fix for both is the same: give each row a
  widget of its own — `itemBuilder: (_, i) => TaskTile(ids[i])` — and read
  in `TaskTile.build`.

### A widget per row

The fix for a lazily built list, in full. The list builds one widget per id,
and each row reads its own query in its own `build`:

```dart snippet="guides/reading-queries-in-widgets.md#device-rows"
ListView.builder(
  itemCount: ids.length,
  // Each row is a widget of its own, so each row's read is its own.
  itemBuilder: (context, index) => DeviceRow(ids[index]),
)
```

```dart snippet="guides/reading-queries-in-widgets.md#device-row"
class DeviceRow extends StatelessWidget {
  const DeviceRow(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final device = context.query(deviceQuery(id));
    return ListTile(title: deviceTitle(device));
  }
}
```

A row scrolled away unmounts and releases its read; one scrolled back in
reads again, from the cache if the entry is still there. Fifty rows are fifty
observers of fifty entries — and each entry, fetched once, is what a detail
screen for that device opens on at once.

[Troubleshooting](../reference/troubleshooting.md) has each of these as a
symptom, with the fix.

## Signals, hooks and other reactive packages

Not dependencies here, and not planned as such. Because a controller is a
`ValueListenable`, a signals package reads it with whatever it offers for
listenables — `signals_flutter` has `valueListenableToSignal`, for one:

```dart snippet="prose-only: needs signals_flutter, which neither published package may depend on"
final task = QueryController.create(client, taskQuery(id));
final signal = valueListenableToSignal(task);        // signals_flutter
final done = computed(() => signal.value.dataOrNull?.done ?? false);
```

Nothing is needed from this package for that.

:::note[In React Query]
`useQuery` is one hook; here it is four shapes of the same observer, because
Flutter has no hooks in the framework. `context.query` and `watchQuery`
read flat in `build`, the way a hook call does. See [differences from TanStack
Query](../reference/differences-from-tanstack.md).
:::
