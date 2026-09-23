---
title: Combining queries
description: combine over a record or a list of results — the pending, error and data rules, optional sources, combineWith, CombineMemo and keys.
---

# Combining queries

Two reads side by side give you two results, and a screen that needs both
has to decide what they amount to: a spinner while either loads, an error if
either failed, and — the part hand-written code gets wrong — what to show
when one of them fails *after* both were on screen. Written as nested
`switch`es, that is nine cases per pair, most of them the same.

A record has a type per position, so `combine` is a function over a **record
of results** — from `context.query`, a builder, the mixin or a controller's
`value`, it does not matter which. Nothing new observes anything: the reads
you already have rebuild the widget, and `combine` says what they amount to
together.

```dart snippet="guides/combining-queries.md#combine"
class TaskWithComments extends StatelessWidget {
  const TaskWithComments(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final combined = (
      context.query(taskQuery(id)),
      context.query(commentsQuery(id)),
    ).combine((task, comments) => '${task.name} (${comments.length})');

    return switch (combined) {
      CombinedPending() => const CircularProgressIndicator(),
      CombinedError(:final error) => TextButton(
          onPressed: combined.retry,
          child: Text('$error — retry'),
        ),
      CombinedData(:final data, :final refetchError) => Text(
          refetchError == null ? data : '$data (could not refresh)',
        ),
    };
  }
}
```

In an app, the combiner is where two lists become the one the screen shows —
here, the rooms, each with the devices in it:

```dart snippet="guides/combining-queries.md#rooms-overview"
// lib/ui/rooms_overview.dart
class RoomsOverview extends StatelessWidget {
  const RoomsOverview({super.key});

  @override
  Widget build(BuildContext context) {
    final rooms = (
      context.query(roomsQuery()),
      context.query(devicesQuery()),
    ).combine(
      (rooms, devices) => <({Room room, List<Device> devices})>[
        for (final room in rooms)
          (
            room: room,
            devices: <Device>[
              for (final device in devices)
                if (device.roomId == room.id) device,
            ],
          ),
      ],
    );

    return switch (rooms) {
      CombinedPending() => const Center(child: CircularProgressIndicator()),
      CombinedError(:final error) => Center(
          child: TextButton(
            onPressed: rooms.retry,
            child: Text('$error — try again'),
          ),
        ),
      CombinedData(:final data) => ListView(
          children: <Widget>[
            for (final entry in data)
              ListTile(
                title: Text(entry.room.name),
                trailing: Text('${entry.devices.length}'),
              ),
          ],
        ),
    };
  }
}
```

The two queries stay separate in the cache — the devices list is the same
entry the devices screen reads, and invalidating it after a rename updates
both screens — and only the view joins them.

The rules, in order:

1. A source that **failed with nothing to show** makes the whole a
   `CombinedError` — it wins over a source that is still loading, because
   waiting does not cure it and `retry()` (which refetches only the failed
   sources) is something a user can press.
2. Otherwise a source with no data yet makes it `CombinedPending`.
3. Otherwise everything has data and the combiner runs. A background refetch
   that failed keeps its stale data in the combination and shows up as
   `refetchError`: content on screen is not blanked.

`isFetching` is "any source is", and `refetch()` refetches all of them. Two to
six results; past six, put the sources in a list typed by what they have in
common — `<QueryResult<Object?>>[a, b, …]` — combine that, and cast in the
combiner. A `CombinedResult` is deliberately not a source, so two combinations
do not nest. Controllers combine the same way under a `ListenableBuilder` over
`Listenable.merge([a, b])`.

`refetch()` and `retry()` call each source's own `refetch()`, with the same
`cancelRefetch` (default `true`). So they cancel a fetch in flight and start
again **only for a source that already has data**; a source still on its
first load, with nothing cached, joins the fetch that is running instead of
restarting it. Two combinations that share a source therefore each refetch
it once it has data. To refresh several combinations at once without
fetching a shared source twice, pass `refetch(cancelRefetch: false)` — the
second call then joins the fetch the first one started.

The combiner runs on every call — every build. For a constructor call that is
nothing; for a join over long lists, keep a `CombineMemo<R>` next to the reads
(a `State` field) and pass it as `memo:`. The combiner is then skipped while
every source holds the identical data instance — which structural sharing
makes the normal case for a refetch that changed nothing — and an equal
result keeps its instance, as TanStack Query shares the output of
`combine`.

A source the screen can do without is `optional()`: it never blocks and never
fails the combination — its value is `null` until there is one — while
`isFetching` still sees it and `retry()` still refetches it when the query
behind it failed. And a **list** of results of one type, a
`QueriesController`'s value, combines by the same rules:

```dart snippet="guides/combining-queries.md#combine-optional-and-lists"
CombinedResult<String> taskWithOptionalComments(
  QueryResult<Task> task,
  QueryResult<List<Comment>> comments,
) =>
    // Still loading, disabled or failed, `comments` is null here — and the
    // task is still the task.
    (task, comments.optional()).combine(
      (task, comments) => '${task.name} (${comments?.length ?? '–'})',
    );

CombinedResult<int> doneCount(List<QueryResult<Task>> tasks) =>
    // A QueriesController's value: one failure with nothing to show wins,
    // otherwise pending, otherwise every value in order.
    tasks.combine((tasks) => tasks.where((task) => task.done).length);
```

A list **and** a source of another type — typically the query the list of
queries was derived from — is `combineWith`. It is one combination, not two
nested ones: the rules read the same, and the deriving query's failure is an
error rather than an empty list. More than one extra source goes the same way
as more than six: one list typed by what the sources have in common, cast in
the combiner.

```dart snippet="guides/combining-queries.md#combine-with"
CombinedResult<List<Comment>> allComments(
  QueryResult<List<Post>> feed,
  List<QueryResult<List<Comment>>> perPost,
) =>
    // One combination, `feed` first: if the query the list was derived from
    // failed, this is an error — not an empty list.
    perPost.combineWith(
      feed,
      (perPost, feed) => [for (final comments in perPost) ...comments],
    );
```

**With a memo, the combiner must be a function of the sources and nothing
else.** A memo cannot see what a closure captures: a combiner that filters by a
search text it closes over keeps returning the list for the *old* text until a
source changes. Do that work on the combined data, after `combine` — or name
what the combiner reads with `keys: [search]`, which is compared with `==` and
re-runs the combiner when it differs.

## See it running

The showcase's *combine* screen joins a post, its comments and a counter.
Set *The post read* to `is refused` and press *Refetch all*: the post's
refetch fails, yet `state=data` holds, with `refetchError=` saying why. Press
*Reset* instead and the post has nothing to show: `state=error`, and a
*Retry* button. With the knob back on `answers` and everything loaded,
*Refetch all* raises `builds` but not `combines` — nothing changed, so the
memo skipped the combiner:

<LiveDemo feature="combine" />

## Traps

- **Combining in a place that does not rebuild.** `combine` observes
  nothing; it reads the results it is handed. Call it where those results are
  read — in the `build` that read them, or under a `ListenableBuilder` over
  the controllers.
- **Blanking on a failed refresh.** Match `CombinedData(:final
  refetchError)` rather than treating every error alike: a refetch that
  failed keeps the data, and a banner is usually all it deserves.
- **A memo over a closure.** See the rule above: with `memo:`, what the
  combiner reads beyond its sources goes in `keys:`.

:::note[In React Query]
This is the `combine` option of `useQueries`, taken out of it: here it works
over any record of results — from any call style — and over a
`QueriesController`'s list. A failure with nothing to show wins over a
source still loading, and `CombineMemo` plays the part of TanStack's
memoised `combine`. See [differences from TanStack
Query](../reference/differences-from-tanstack.md).
:::
