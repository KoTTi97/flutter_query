---
title: Query cancellation
description: Every query function receives a QueryCancelToken — bridging it to dio and package:http, stopping work done in steps, and what cancelQueries, a leaving screen and a refetch each do to a fetch in flight.
---

# Query cancellation

The user opens a device's history, which takes three seconds to load over a
slow link, and backs out after one. The request is still running. Its answer
will be cached, which is fine — but if the transport could stop it, the
phone would save the bandwidth and the gateway the work.

Every query function receives `context.signal`, a `QueryCancelToken`. It is
cancelled when the fetch is no longer wanted. What it cannot do by itself is
stop your HTTP request, because Dart has no cancellation primitive that every
HTTP client understands — so the token's `onCancel` is the bridge you build
once, in the repository.

| On `QueryCancelToken` | |
|---|---|
| `onCancel(callback)` | run `callback` when the fetch is cancelled — at once, if it already is. Callbacks run synchronously inside the cancel |
| `isCancelled` | whether it has been cancelled; once true, it stays true |
| `whenCancelled` | a future that completes on cancellation, and never otherwise |
| `throwIfCancelled()` | throws a `CancelledError` if it has been cancelled |

One token is created per fetch and shared by that fetch's retries. A query
function never cancels it itself.

## With dio

dio has its own `CancelToken`. Create one per request and cancel it from the
query's token:

```dart snippet="prose-only: needs dio, which neither published package may depend on"
// lib/data/device_repository.dart
class DeviceRepository {
  DeviceRepository(this._dio);

  final Dio _dio;

  Future<List<Device>> list({QueryCancelToken? signal}) async {
    final cancelToken = CancelToken();
    signal?.onCancel(cancelToken.cancel);
    final response = await _dio.get<List<Object?>>(
      '/devices',
      cancelToken: cancelToken,
    );
    return [
      for (final json in response.data!)
        Device.fromJson(json! as Map<String, Object?>),
    ];
  }
}
```

and the query hands the signal over:

```dart snippet="excerpt: guides/background-fetching-indicators.md#device-queries"
QueryObserverOptions(
  queryKey: DeviceKeys.list,
  queryFn: (context) => deviceRepository.list(signal: context.signal),
  // …
)
```

A cancelled dio request throws a `DioException` of type `cancel`. You do not
need to catch it: by then the library has already settled the fetch as
cancelled, and the function's late error is dropped.

## With `package:http`

Since version 1.5, `package:http` can abort a request through a future — and
`whenCancelled` is one:

```dart snippet="prose-only: needs package:http, which neither published package may depend on"
Future<List<Device>> list({QueryCancelToken? signal}) async {
  final request = http.AbortableRequest(
    'GET',
    Uri.parse('$baseUrl/devices'),
    abortTrigger: signal?.whenCancelled,
  );
  final response = await http.Response.fromStream(await _client.send(request));
  return decodeDevices(response.body);
}
```

With an older `package:http`, or any client that cannot abort, register
nothing: the request runs to completion and its answer is thrown away. That
is also what TanStack Query does with a `fetch` that ignores its signal.

## Work done in steps

A function that does its work in several requests — reading a long log off
a device in chunks — checks between steps, so a cancel stops it at the next
boundary:

```dart snippet="guides/query-cancellation.md#steps"
// Reading a long log off a device, chunk by chunk, over a slow link.
Future<List<String>> readDeviceLog(
  QueryFunctionContext context,
  String deviceId,
) async {
  final signal = context.signal;
  final lines = <String>[];
  for (var chunk = 0; chunk < 20; chunk++) {
    signal.throwIfCancelled(); // nobody wants the rest
    lines.addAll(
      await deviceRepository.readLog(deviceId, chunk, signal: signal),
    );
  }
  return lines;
}
```

## When a fetch is cancelled

**The last reader leaves** while the fetch runs — the screen was closed, the
search term changed. What happens depends on whether the function *read*
`context.signal`:

- **It read the signal.** Reading it says "I can be stopped". The fetch is
  cancelled and the query goes back to the state it held before the fetch
  started: a list that had data keeps it; a first load goes back to
  `pending`, `idle`.
- **It never read the signal.** The request cannot be stopped, so it is left
  to finish, and its answer is cached for the next reader. Only further
  retries are called off. (A first load paused while
  [offline](network-mode.md) is cancelled either way — no request is out.)

**`client.cancelQueries(filters: …)`** cancels matching fetches on request —
a *Stop* button, or the first step of an
[optimistic update](optimistic-updates.md), so that a refetch in flight
cannot overwrite the optimistic data:

```dart snippet="guides/query-cancellation.md#cancel-button"
class CancelLogButton extends StatelessWidget {
  const CancelLogButton({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => QueryClientProvider.read(context)
            .cancelQueries(
              filters: QueryFilters(queryKey: deviceLogKey(deviceId)),
            )
            .ignore(),
        child: const Text('Stop reading'),
      );
}
```

**A refetch with `cancelRefetch: true`** — the default for a result's
`refetch()`, `invalidateQueries` and `refetchQueries` — cancels the fetch in
flight and starts its own, when the query already has data. A query still
loading its first data joins the running fetch instead.

**Search as you type** gets cancellation for free when each term is its own
key: a new term is a new query, the old one loses its last reader, and a
function that read the signal is cancelled.

Try it: the screen below starts its slow fetch as it opens, so wait the
three seconds until *Start slow fetch* is enabled, then press it and *Cancel*
within three seconds. `cancels=` goes up — the token reached the HTTP
client — and `fetchStatus=` is back to `idle`. Turn on *Ignore the signal*
and repeat: the query is cancelled all the same and `cancels=` stays put,
because nothing told the client to stop; the backend answers in full and the
answer is dropped. Below it, type into *Search posts*: each new term cancels
the one still in flight.

<LiveDemo feature="cancellation" height={640} />

## What `cancelQueries` does

| Option | Default | Effect |
|---|---|---|
| `revert` | `true` | each query goes back to the state it held before the fetch, `fetchStatus` `idle` |
| `silent` | `false` | `true` means "a new fetch is taking over": nothing is recorded as an error |

With the defaults, a reader keeps the data it had, and whoever awaited the
fetch — `client.query`, a `refetch()` — gets that data back, or a
`CancelledError` when there was none. A silently cancelled fetch that nothing
replaces is put back to `idle` rather than left `fetching`.

The returned future completes when every matching cancel has settled, and
never fails.

A cancelled fetch is never retried. With `revert` (the default) it leaves no
error on the result; `revert: false` without `silent` records the
`CancelledError` as the query's error.

## Disconnecting a device

To stop talking to something — a device the user removed — cancel its
queries and remove them, so nothing refetches them:

```dart snippet="reference/troubleshooting.md#disconnect"
void disconnect(QueryClient client, QueryKey deviceKey) {
  final filters = QueryFilters(queryKey: deviceKey);
  client.cancelQueries(filters: filters).ignore();
  client.removeQueries(filters: filters);
}
```

Cancelling a *mutation* works differently — it fails the run; see
[cancelling mutations](cancelling-mutations.md).

:::note[In React Query]
`context.signal` is an `AbortSignal` there, handed straight to `fetch` or
axios; here it is a `QueryCancelToken`, and `onCancel` or `whenCancelled` is
the bridge to your HTTP client. Reading the signal marks the fetch as
cancellable in both. A silent cancel with no successor stays `fetching`
there and goes back to `idle` here. See
[differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
