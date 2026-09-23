---
title: Background fetching indicators
description: isFetching on a result for one query's refresh, and IsFetchingController for an app-wide indicator of any fetch in flight.
---

{/* depth: todo */}
{/* demo: parallel-queries */}

# Background fetching indicators

A query's `status` says whether it has data; its `fetchStatus` says whether a
request is running. A background refetch is `success` **and** `fetching`, so
the screen can keep showing the data and add a quiet indicator.

## One query

`result.isFetching` is true while any fetch of that query runs — the first
load and every refetch. `result.isRefetching` is the background case alone:
fetching while not pending. See [queries](queries.md#what-the-query-is-doing-fetchstatus).

## Every query

`IsFetchingController` counts the queries fetching right now — the counterpart
of `useIsFetching`. It is a `ValueListenable<int>`:

```dart snippet="guides/background-fetching-indicators.md#global-indicator"
class FetchingBar extends StatefulWidget {
  const FetchingBar({super.key});

  @override
  State<FetchingBar> createState() => _FetchingBarState();
}

class _FetchingBarState extends State<FetchingBar> {
  late final IsFetchingController _fetching =
      IsFetchingController(QueryClientProvider.read(context));

  @override
  void dispose() {
    _fetching.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: _fetching,
        builder: (context, count, _) => count == 0
            ? const SizedBox(height: 2)
            : const LinearProgressIndicator(minHeight: 2),
      );
}
```

`QueryClientProvider.read` looks the client up without subscribing to the
provider, which is what a `late final` field initialiser wants.

Pass `filters:` to count only some queries — `QueryFilters(queryKey:
tasksKey)` for a bar over the task list alone. Without a widget,
`client.isFetching(filters: …)` is the same count, once.

For writes, `client.isMutating()` counts mutations in flight; to subscribe to
them, see [mutation state](mutation-state.md).
