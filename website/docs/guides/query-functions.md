---
title: Query functions
description: A query function returns a Future and throws on failure — a repository on dio or package:http, error types a retry policy can read, cancellation, and what the function context carries.
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# Query functions

The cache does not know about HTTP. It knows one thing about a fetch: whether
the `Future` it was handed completed with a value or with an error. Everything
else — retries, `QueryError`, `failureCount`, the error callbacks — starts
there, and so does the most common bug in a new integration: a server error
that never became a Dart error, cached as if it were the data.

A query function is any function that returns a `Future` of the data. It
receives a `QueryFunctionContext`, and it has one job besides fetching:
**throw when it fails.**

```dart snippet="excerpt: guides/queries.md#device-queries"
QueryObserverOptions<Device> deviceQuery(String id) => QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => repository.device(id, signal: context.signal),
    );
…
```

## Where the function lives

A `queryFn` is usually one line that calls a repository — the class in
`lib/data/` that knows the backend's paths, parses its JSON and turns its
refusals into exceptions. The query layer stays free of HTTP, and the
repository stays free of caching.

The repository's error type is worth its few lines. Whatever you throw is the
`error` on the result, what a `QueryListener` shows and what your `retry`
policy is handed, so throw something your UI and your policy can tell apart:

```dart snippet="guides/query-functions.md#api-exception"
/// What the repository throws when the backend refuses.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;

  /// The HTTP status, or null when no response arrived at all.
  final int? statusCode;

  /// A 4xx: asking again will not change the answer.
  bool get isClientError =>
      statusCode != null && statusCode! >= 400 && statusCode! < 500;

  @override
  String toString() => message;
}
```

## Throwing is how a query fails

Here the two common HTTP clients differ, and the difference matters:

- **dio** throws a `DioException` for a non-2xx response by default. A
  function built on it fails correctly as written; the repository's job is to
  turn the exception into its own type.
- **`package:http` does not throw** on a 4xx or 5xx response: it returns the
  response. A repository built on it has to check `statusCode` and throw
  itself, or a 404 page is cached as a success.

The same repository method on each, with the cache's cancellation handed on
to the transport:

<Tabs groupId="http-client">
<TabItem value="dio" label="dio">

```dart snippet="prose-only: built on dio 5, which this documentation's compiled samples may not depend on"
// lib/data/device_repository.dart
class DeviceRepository {
  DeviceRepository(this._dio);

  final Dio _dio;

  Future<Device> device(String id, {QueryCancelToken? signal}) async {
    final json = await _get('/devices/$id', signal);
    return Device.fromJson(json! as Map<String, Object?>);
  }

  Future<Object?> _get(String path, QueryCancelToken? signal) async {
    // The cache's cancellation, handed on to dio.
    final cancelToken = CancelToken();
    signal?.onCancel(cancelToken.cancel);
    try {
      final response = await _dio.get<Object?>(path, cancelToken: cancelToken);
      return response.data;
    } on DioException catch (error) {
      // Cancelled because nobody wants the answer: not a failure to report.
      if (CancelToken.isCancel(error)) rethrow;
      // dio throws for any non-2xx status; make it an error the app knows.
      throw ApiException(
        error.message ?? 'Request failed',
        statusCode: error.response?.statusCode,
      );
    }
  }
}
```

</TabItem>
<TabItem value="http" label="package:http">

```dart snippet="prose-only: built on package:http 1.5, which this documentation's compiled samples may not depend on"
// lib/data/device_repository.dart
class DeviceRepository {
  DeviceRepository(this._client, this._baseUrl);

  final http.Client _client;
  final Uri _baseUrl;

  Future<Device> device(String id, {QueryCancelToken? signal}) async {
    final json = await _get('devices/$id', signal);
    return Device.fromJson(json! as Map<String, Object?>);
  }

  Future<Object?> _get(String path, QueryCancelToken? signal) async {
    // package:http aborts a request when this future completes.
    final abort = Completer<void>();
    signal?.onCancel(abort.complete);

    final request = http.AbortableRequest(
      'GET',
      _baseUrl.resolve(path),
      abortTrigger: abort.future,
    );
    final response = await http.Response.fromStream(
      await _client.send(request),
    );

    // A 404 or a 500 is a response here, not an exception: check it, or the
    // error page is cached as the data.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Request failed with ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    return jsonDecode(response.body);
  }
}
```

`AbortableRequest` needs `package:http` 1.5 or later. On an older version,
leave the signal unread: the request then runs to its end and the cache drops
the answer it no longer wants.

</TabItem>
</Tabs>

Both use `import 'package:query_kit/query_kit.dart'` for `QueryCancelToken`,
so the data layer needs no Flutter. With an error type in hand, a retry
policy can stop wasting attempts on answers that will not change:

```dart snippet="guides/query-functions.md#retry-on-status"
// A 404 or a 403 will not change on the third try; a timeout might.
retry: RetryPolicy.when(
  (failureCount, error, _) =>
      failureCount < 3 && !(error is ApiException && error.isClientError),
),
```

See [query retries](query-retries.md) for the rest of the policy.

## The context

`QueryFunctionContext` carries:

- **`signal`** — a `QueryCancelToken` that is cancelled when the fetch is no
  longer wanted: the query was cancelled, or its last reader left while it
  ran. Reading `signal` is what marks the fetch as cancellable, so read it
  only if you hand it on. `onCancel(callback)` runs the callback on cancel —
  at once, if that has already happened — and `isCancelled`,
  `throwIfCancelled()` and `whenCancelled` cover a function that does its own
  work in steps. See [query cancellation](query-cancellation.md).
- **`queryKey`** — the key being fetched, so one function can serve a whole
  family of keys.
- **`meta`** — the query's `meta` option, for information that is not part of
  the key (a logging tag, a toast policy — see [global
  callbacks](global-callbacks.md)).
- **`client`** — the `QueryClient` running the fetch.

One function for a family of keys reads what it needs back from the key:

```dart snippet="guides/query-functions.md#from-key"
// One function for every detail key: the id is read back from the key.
Future<Device> fetchDevice(QueryFunctionContext context) {
  final id = context.queryKey.parts[2]! as String;
  return repository.device(id, signal: context.signal);
}
```

The key's parts are `Object?`, so reading one back is a cast. That is the
price of one shared function; a function per query that closes over its `id`
has none. See also [default query function](default-query-function.md).

An infinite query's function is `pageFn`, handed an `InfinitePageContext`
that also carries the `pageParam` and the `direction`; see [infinite
queries](infinite-queries.md).

The showcase's *cancellation* screen shows what handing the signal on buys.
Press *Start slow fetch*, then *Cancel*: the query goes back to where it was
and `cancels` counts one `onCancel`. Switch *Ignore the signal* on and do it
again — the query is still cancelled, but `cancels` stays put: the request ran
to its end at the backend and only its answer was thrown away:

<LiveDemo feature="cancellation" />

## Traps

- **Swallowing the error.** A `try`/`catch` that logs and returns an empty
  list turns every failure into a success — no retry, no error state, and an
  empty list cached as the truth. Catch to *translate*, then throw.
- **Catching the cancellation.** When the cache cancels, the transport throws
  (dio a cancelled `DioException`, `package:http` a
  `RequestAbortedException`). Rethrow it or let it pass; the cache has
  already settled the query's state and drops what the function does next.
- **Reading widget state.** The function runs when the cache decides — on
  mount, on focus, on reconnect, on an invalidation — possibly after the
  widget that first asked is gone. It reads everything from the key and from
  stable objects it closes over (a repository), never from a `BuildContext`.
- **A parse error is a failure too.** A `TypeError` from a missing JSON field
  fails the query like any other error — and is retried three times by
  default. Parse inside the repository and throw your own type if the message
  should reach a user.

:::note[In React Query]
The same contract as `queryFn` in TanStack Query: resolve with data or throw.
`signal` is a `QueryCancelToken` rather than an `AbortSignal`, because Dart
has no cancellation primitive every HTTP client shares; `onCancel` is the
bridge. `fetch`'s "does not reject on 4xx" trap is `package:http`'s here. See
[differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
