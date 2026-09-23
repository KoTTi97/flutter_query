---
title: Disabling queries
description: Enabled.no keeps a query from fetching on its own — a query run only on demand, a search that waits for input, what a disabled query still does, and why there is no skipToken.
---

# Disabling queries

Most queries should fetch as soon as a screen shows them. A few should not: a
network scan that floods the local network for ten seconds, a report that
costs the server a minute, a search box with nothing typed in it yet. For
those, the question is not *when is the data stale* but *should this run at
all* — and the answer is `enabled`.

`enabled: Enabled.no` keeps a query from fetching on its own: not on mount,
not on focus or reconnect, not on an interval, not on an invalidation.

## On demand: `refetch`

A disabled query still fetches when asked to. A scan for new devices in a
smart-home app runs only when the user presses the button:

```dart snippet="guides/disabling-queries.md#discovery"
QueryObserverOptions<List<Device>> discoveryQuery() => QueryObserverOptions(
      queryKey: QueryKey(<Object?>['discovery']),
      queryFn: (context) => repository.discover(signal: context.signal),
      // A scan floods the local network: run it only when asked to.
      enabled: Enabled.no,
    );

class ScanButton extends StatelessWidget {
  const ScanButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scan = context.query(discoveryQuery());

    return Column(
      children: <Widget>[
        FilledButton(
          onPressed: scan.isFetching ? null : scan.refetch,
          child: Text(scan.isFetching ? 'Scanning…' : 'Scan for devices'),
        ),
        if (scan case QuerySuccess(:final data))
          Text('${data.length} new devices found'),
      ],
    );
  }
}
```

The button reads the same result it triggers: `isFetching` while the scan
runs, `QuerySuccess` once it answered. Because the result is in the cache
under its key, leaving the screen and coming back shows the last scan at
once, for as long as the entry is cached — and does not start a new one.

## Waiting for input: a lazy query \{#lazy-queries\}

A search should not run for an empty box. Disable the query until there is
input worth sending, and put the input in the key:

```dart snippet="guides/disabling-queries.md#search-query"
QueryObserverOptions<List<Device>> deviceSearchQuery(String text) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.all.append(<Object?>['search', text]),
      queryFn: (context) => repository.search(text, signal: context.signal),
      // One letter matches half the house: wait for two.
      enabled: text.length >= 2 ? Enabled.yes : Enabled.no,
    );
```

Each text is its own cache entry, so typing back to an earlier text shows its
results at once. The screen then tells "waiting to be enabled" from "loading"
by `isFetching`:

```dart snippet="guides/disabling-queries.md#search-screen"
class _DeviceSearchState extends State<DeviceSearch> with QueryMixin {
  String _text = '';

  @override
  Widget build(BuildContext context) {
    final results = watchQuery(deviceSearchQuery(_text));

    return Column(
      children: <Widget>[
        TextField(
          decoration: const InputDecoration(labelText: 'Find a device'),
          onChanged: (text) => setState(() => _text = text.trim()),
        ),
        switch (results) {
          // Disabled: pending, and nothing is running. A hint, not a spinner.
          QueryPending(isFetching: false) =>
            const Text('Type two letters or more'),
          QueryPending() => const LinearProgressIndicator(),
          QueryError(:final error) => Text('Search failed: $error'),
          QuerySuccess(:final data) => Expanded(child: DeviceListView(data)),
        },
      ],
    );
  }
}
```

While the box holds less than two letters, the result is `pending` and not
fetching: a hint, not a spinner. `result.isLoading` — pending **and**
fetching — is the flag for a spinner; it is `false` for a query that is only
waiting to be enabled.

A lazy query and a [dependent query](dependent-queries.md) are the same
mechanism: `enabled` computed from something the query needs. The showcase's
*dependent queries* screen has both: its comments wait for a post, and the
*Pause comments* box disables them outright. Choose a post with the box
ticked and the *Comments* card says *Paused: no request until the box is
unticked.*; untick it and the request goes out:

<LiveDemo feature="dependent-queries" />

## What a disabled query still does

- It **serves cached data**. Without data it is `pending` with `fetchStatus:
  idle`; with data it stays `success`.
- **`refetch()` still fetches**, as above.
- **`invalidateQueries` marks it invalidated** but does not refetch it
  while a disabled observer holds it — and its result's `isStale` stays
  `false`, because a disabled query is never stale. Once it is enabled, the
  invalidation counts. `refetchQueries` skips it too.
- Once **nothing observes** a query that has fetched before,
  `refetchQueries` and `invalidateQueries(refetchType: RefetchType.all)`
  refetch it whatever `enabled` its last observer had.

## Traps

- **`Enabled.no` for data that should simply be fresh longer.** A query
  disabled so that it "does not refetch so often" also never loads on a
  new screen. That is a `staleTime`, not a switch — see [important
  defaults](../important-defaults.md).
- **Driving a disabled query with `refetch` from `initState`.** That is an
  enabled query with extra steps, minus the refetches on focus and on
  reconnect. Reserve `Enabled.no` plus `refetch` for work a user asks for.
- **A disabled query with the input outside its key.** A search disabled
  until there is text, keyed without the text, shows the previous search's
  results for the new text.

:::note[In React Query]
`enabled: false` is `Enabled.no`, and there is no `skipToken`. Where the two
differ upstream, `Enabled.no` behaves like `enabled: false`: an unobserved
query that fetched before is refetched by `refetchQueries` and
`invalidateQueries(refetchType: RefetchType.all)`, where `skipToken` would
skip it. See [differences from TanStack
Query](../reference/differences-from-tanstack.md).
:::
