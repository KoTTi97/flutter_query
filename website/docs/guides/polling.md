---
title: Polling
description: RefetchInterval refetches on a timer while a reader is subscribed — every, dynamic, in the background or not, and giving up after failures in a row.
---

{/* depth: todo */}
{/* demo: auto-refetching */}

# Polling

`refetchInterval` refetches a query on a timer for as long as something reads
it.

| | |
|---|---|
| `RefetchInterval.off` | the default: no polling |
| `RefetchInterval.every(d)` | refetch every `d` |
| `RefetchInterval.dynamic((query) => …)` | computed from the query each time the timer is re-armed; return a `Duration`, or `null` to stop |

Each reader's observer has its own timer: it starts when that reader
subscribes and stops when it goes. It polls whatever `staleTime` says, including
a `StaleTime.static` query.

## In the background

`refetchIntervalInBackground` keeps a poll running while the app is not
focused. By default it is `false`, and polling pauses when the app goes to
the background — see [app focus refetching](window-focus-refetching.md) for
what counts as focused on each platform.

## Pausing a poll

A poll that must stop while something else happens — a write in flight — is
a value in the options, chosen in `build`:

```dart snippet="reference/troubleshooting.md#pause-polling"
QueryObserverOptions<List<Task>> polledTasks({required bool writing}) =>
    QueryObserverOptions(
      queryKey: tasksKey,
      queryFn: (context) => api.listTasks(signal: context.signal),
      // A value, not a callback: the widget rebuilds when `writing` flips,
      // hands over new options, and the observer sees that they changed.
      refetchInterval: writing
          ? RefetchInterval.off
          : const RefetchInterval.every(Duration(seconds: 1)),
    );
```

A `RefetchInterval.dynamic` that reads outside state is asked only when the
timer is re-armed, so it would notice the change one tick late.

## Giving up after failures

To stop after failures in a row, read `consecutiveErrorCount` from the
query's state: one more with every fetch that ends in an error (its retries
exhausted), back to zero with the next data that is **fetched**. A manual
write — an optimistic patch — leaves it alone, and so does a cancelled fetch:
neither says whether the source answers.

```dart snippet="guides/polling.md#stop-polling-after-failures"
const RefetchInterval giveUpAfterFive = RefetchInterval.dynamic(_untilFiveFail);

Duration? _untilFiveFail(Query<Object?> query) =>
    query.state.consecutiveErrorCount >= 5 ? null : const Duration(seconds: 1);
```

The same count is on the result as `result.consecutiveErrorCount`, for the
widget that says "the device has not answered five times".

A top-level function, as here, is one value on every build, so the options
compare as unchanged; see [describing a query
once](query-options.md#options-built-in-build-are-fine).
