---
title: Polling
description: refetchInterval refetches a query on a timer while a reader is on screen — fixed or computed intervals, polling in the background, stopping when the server confirms, and giving up after failures in a row.
---

# Polling

Some data changes where the app cannot see it happen. A thermostat reports a
new temperature, a shutter finishes moving, a firmware update installs on a
device. Nothing in the app invalidates those queries, because nothing in the
app caused the change — so the screen that shows them asks again on a timer.

`refetchInterval` takes a `RefetchInterval`:

| | |
|---|---|
| `RefetchInterval.off` | the default: no polling |
| `RefetchInterval.every(d)` | refetch every `d` |
| `RefetchInterval.dynamic((query) => …)` | computed from the query; return a `Duration`, or `null` to stop |

```dart snippet="guides/polling.md#every"
// A thermostat's reading changes on its own; nothing in the app invalidates
// it, so the screen that shows it asks every five seconds.
QueryObserverOptions<Device> thermostatQuery(String id) => QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => deviceRepository.byId(id, signal: context.signal),
      refetchInterval: const RefetchInterval.every(Duration(seconds: 5)),
    );
```

Polling belongs to the **reader**, not to the cache entry. Each reader's
observer has its own timer: it starts when the reader subscribes and stops
when it goes, so leaving the thermostat screen stops its poll with nothing
to clean up. Two widgets reading the same key with different intervals each
poll at their own; both refetch the one shared entry.

The interval is independent of `staleTime`. A query polls on schedule whether
its data is fresh or not — a `StaleTime.static` query included — and each
poll is an ordinary refetch: the data stays on screen, `isRefetching` is
true while it runs, and [structural sharing](structural-sharing.md) keeps the
rows that did not change.

Try it: in the screen below, pick `500 ms` and watch the strip's `fetches=`
grow; *Add tick* shows up by the next poll at the latest. Pick `dynamic` and
the poll stops by itself once the list has three ticks — *Clear ticks* starts
it again.

<LiveDemo feature="auto-refetching" />

## An interval computed from the data

`RefetchInterval.dynamic` is asked for the next interval whenever the query
changes — each fetch starting and ending — and when the reader's options
change. Returning `null` stops the timer; returning a duration again later
starts it. That makes "poll until something is true" a few lines.

### Poll until the server confirms

A firmware update is started with a write that the server accepts with
`202 Accepted` and a job id; the device installs it over the next minute.
The screen polls the job until the server says it is done — or until the
device has not answered five times in a row:

```dart snippet="guides/polling.md#until-confirmed"
// lib/data/firmware_queries.dart
QueryKey firmwareJobKey(String jobId) =>
    QueryKey(<Object?>['firmware-job', jobId]);

QueryObserverOptions<FirmwareJob> firmwareJobQuery(String jobId) =>
    QueryObserverOptions(
      queryKey: firmwareJobKey(jobId),
      queryFn: (context) =>
          deviceRepository.firmwareJob(jobId, signal: context.signal),
      refetchInterval: const RefetchInterval.dynamic(_untilTheJobSettles),
    );

Duration? _untilTheJobSettles(Query<Object?> query) => switch (query.state) {
      QueryState(data: FirmwareJob(done: true)) => null, // confirmed: stop
      QueryState(consecutiveErrorCount: >= 5) => null, // gone quiet: stop
      _ => const Duration(seconds: 2),
    };
```

The callback receives the query untyped, because one `RefetchInterval` value
can be shared by queries of any type; a pattern on `query.state` reads the
data back.

The widget shows the three outcomes. Nothing in it owns a timer or a
counter:

```dart snippet="guides/polling.md#job-progress"
class FirmwareProgress extends StatelessWidget {
  const FirmwareProgress({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context) {
    final job = context.query(firmwareJobQuery(jobId));
    return switch (job) {
      QuerySuccess(data: FirmwareJob(done: true)) =>
        const Text('Update installed'),
      _ when job.consecutiveErrorCount >= 5 =>
        const Text('The device stopped answering. Check it and try again.'),
      _ => const LinearProgressIndicator(),
    };
  }
}
```

When the job reports done, the device itself has a new firmware version: the
write's `onSuccess` is the wrong moment to invalidate it, and a
[listener](side-effects.md) on the job's result is the right one.

### Giving up after failures

`consecutiveErrorCount` is on the query's state and on the result: one more
with every fetch that ends in an error (its retries exhausted), back to zero
with the next data that is **fetched**. A manual write — an optimistic patch,
`setQueryData` — leaves it alone, and so does a cancelled fetch: neither says
whether the source answers. That is what makes it the right thing to count;
the result's variant is not, since a manual write turns a `QueryError` into
a `QuerySuccess` while the device is still silent.

The stopping rule on its own, as a value to reuse:

```dart snippet="guides/polling.md#stop-polling-after-failures"
const RefetchInterval giveUpAfterFive = RefetchInterval.dynamic(_untilFiveFail);

Duration? _untilFiveFail(Query<Object?> query) =>
    query.state.consecutiveErrorCount >= 5 ? null : const Duration(seconds: 1);
```

Each of those failures has already been [retried](query-retries.md) — three
times with backoff by default — so five failed polls are twenty requests.
For a poll, fewer retries are often the better trade: the next tick is a
retry of its own.

A top-level function, as here, is one value on every build, so the options
compare as unchanged; see [describing a query
once](query-options.md#options-built-in-build-are-fine).

## In the background

By default a poll skips its turns while the app is unfocused and picks up
again when the user comes back — see
[app focus refetching](window-focus-refetching.md) for what counts as
focused on each platform. `refetchIntervalInBackground: true` keeps it
running:

```dart snippet="guides/polling.md#background"
// A wall-mounted dashboard on a desktop: keep it current while another
// window is in front.
QueryObserverOptions<List<Device>> dashboardQuery() => QueryObserverOptions(
      queryKey: DeviceKeys.list,
      queryFn: (context) => deviceRepository.list(signal: context.signal),
      refetchInterval: const RefetchInterval.every(Duration(minutes: 1)),
      refetchIntervalInBackground: true,
    );
```

:::warning[A phone suspends a backgrounded app]
On iOS and Android the operating system stops a backgrounded app's Dart code
soon after it leaves the screen, timers included. The flag keeps a poll
going on the desktop, on the web, and for the moments before the phone
suspends the app — it cannot make a phone poll in its pocket. Work that must
happen in the background is the platform's (push notifications, background
fetch), not a query's.
:::

## Pausing a poll

A poll that must stop while something else happens — a write in flight, a
dialog open — is a value in the options, chosen in `build`:

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

A `RefetchInterval.dynamic` that reads outside state instead is asked only
when the query or the options change, so it notices the flag at the next
poll at the earliest — one tick late.

## Testing a poll

A poll is a timer. In a widget test, `pumpAndSettle` does not step it —
nothing schedules a frame while the timer waits — so advance time with
`tester.pump(interval)`. See [testing](testing.md).

:::note[In React Query]
`refetchInterval` takes milliseconds, `false` or a function returning
either; here `RefetchInterval.every`, `off` and `dynamic`, with `null` for
"stop". `refetchIntervalInBackground` is the same flag, with the app
lifecycle standing in for the browser tab's visibility.
`consecutiveErrorCount` has no counterpart in TanStack Query. See
[differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
