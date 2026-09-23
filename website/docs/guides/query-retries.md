---
title: Query retries
description: A failed query is retried before the error reaches the screen — RetryPolicy and RetryDelay, not retrying a 4xx, honouring Retry-After, and showing the attempts in the UI.
---

# Query retries

Mobile networks drop requests. A lift, a tunnel, a handover between cells —
the first attempt times out and the second one works. So a query whose
function throws is not an error on screen straight away: it is retried,
**three more times** by default, waiting one second, then two, then four.
Only when those run out does the result become a `QueryError`.

That default suits a flaky connection and is wrong for a request the server
refused on purpose. A 404 will be a 404 on the fourth attempt too, and the
user waits seven seconds to learn it. This page is about telling the two
apart.

## `RetryPolicy`

`retry` takes a `RetryPolicy`:

| | |
|---|---|
| `RetryPolicy.times(n)` | retry up to `n` times after the first failure, so at most `n + 1` attempts — `times(3)` is the query default |
| `RetryPolicy.never` | the first failure is the error — the mutation default |
| `RetryPolicy.always` | retry until an attempt succeeds |
| `RetryPolicy.when((failureCount, error, stackTrace) => …)` | decide per failure; `failureCount` is how many attempts had failed **before** this one, so `0` on the first decision |

Set it on a query, or for every query in the client's defaults:

```dart snippet="guides/query-retries.md#client-defaults"
QueryClient deviceAppClient() => QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(
          retry: RetryPolicy.times(2),
          retryDelay: RetryDelay.exponential(
            base: Duration(milliseconds: 500),
            maximum: Duration(seconds: 8),
          ),
        ),
      ),
    );
```

### Not retrying what will not change

`RetryPolicy.when` is where a policy looks at the error. The app's HTTP
layer throws its own exception with the status code (see
[query functions](query-functions.md#throwing-is-how-a-query-fails)), and the
policy retries server errors and transport failures but not a client error:

```dart snippet="guides/query-retries.md#server-errors-only"
const RetryPolicy retryServerErrors = RetryPolicy.when(_retryServerErrors);

bool _retryServerErrors(int failureCount, Object error, StackTrace _) =>
    failureCount < 3 &&
    switch (error) {
      // 4xx: the request is wrong, and asking again will not change that.
      ApiException(:final statusCode) => statusCode >= 500,
      // A timeout or a dropped connection may well work the second time.
      _ => true,
    };
```

With dio, the same rule reads the `DioException` the client throws:

```dart snippet="prose-only: needs dio, which neither published package may depend on"
bool retryServerErrors(int failureCount, Object error, StackTrace _) {
  if (failureCount >= 3) return false;
  if (error is! DioException) return true;
  return switch (error.type) {
    DioExceptionType.badResponse =>
      (error.response?.statusCode ?? 0) >= 500,
    DioExceptionType.badCertificate => false,
    // Timeouts, connection errors: worth another try.
    _ => true,
  };
}
```

The narrower version, for the one status you know is final:

```dart snippet="guides/query-retries.md#retry-when"
const RetryPolicy retryUnlessNotFound = RetryPolicy.when(_retryUnlessNotFound);

bool _retryUnlessNotFound(int failureCount, Object error, StackTrace _) =>
    failureCount < 3 && !(error is HttpError && error.statusCode == 404);
```

A top-level function keeps the policy `const` — one value on every build,
so the options compare as unchanged. An inline closure is a new value each
time.

A policy that throws does not leave the fetch hanging: the throw becomes the
fetch's error.

## `RetryDelay`

`retryDelay` takes a `RetryDelay`:

| | |
|---|---|
| `RetryDelay.exponential()` | the default: one second, doubling, capped at thirty; `base:` and `maximum:` change both |
| `RetryDelay.fixed(d)` | the same wait before every retry |
| `RetryDelay.dynamic((failureCount, error) => …)` | computed per failure; `failureCount` is `0` before the first retry |

`RetryDelay.dynamic` sees the error, so a server that says how long to wait
can be taken at its word — and everything else falls back to the default
backoff:

```dart snippet="guides/query-retries.md#retry-after"
const RetryDelay honourRetryAfter = RetryDelay.dynamic(_retryAfter);

Duration _retryAfter(int failureCount, Object error) => switch (error) {
      ApiException(:final retryAfter?) => retryAfter,
      _ => RetryDelay.defaultValue.resolve(failureCount, error),
    };
```

The delay is only asked when the policy has decided to retry.

## While it retries

The fetch is still running while it retries, so the result stays what it
was — `QueryPending` on a first load, `QuerySuccess` with its data on a
refresh — with `isFetching` true. Two fields report the attempts:

- **`failureCount`** — attempts that have failed in the current fetch.
- **`failureReason`** — what the latest one threw. It stays set through the
  retries and after the fetch finally fails, and is cleared when the next
  fetch starts or an attempt succeeds.

So a loading state can say it is struggling without owning a counter:

```dart snippet="guides/query-retries.md#attempts"
Widget devicesStatus(QueryResult<List<Device>> devices) => switch (devices) {
      QueryPending(failureCount: 0) => const Text('Loading devices…'),
      QueryPending(:final failureCount, :final failureReason) =>
        Text('Still trying (attempt ${failureCount + 1}): $failureReason'),
      QueryError(:final error) => Text('Could not load devices: $error'),
      QuerySuccess(:final data) => Text('${data.length} devices'),
    };
```

When the retries run out, the result is a `QueryError`. On a first load its
`isLoadingError` is true; on a refresh, `isRefetchError` is, and
`staleData` still holds what the screen was showing.

Try it: in the screen below, pick *Retry* `2 times`, set *Fail the next* to
`2`, press *Arm* and then refetch. `failureCount=` climbs to 1 and 2 while
`failureReason=` names the refusal, and the third attempt succeeds. With
`10` failures armed, the same policy ends in an error after three requests.

<LiveDemo feature="retry" height={640} />

## In the background

A retry waits for the app to be in front and, under the default
[network mode](network-mode.md), for the network. If the app goes to the
background or the client learns it is offline between attempts, the fetch
**pauses** — `fetchStatus` `paused`, `isPaused` true — and continues with its
next attempt when both are back, rather than spending its retries where
nobody is looking.

## Mounting on an error

When a query with no data runs out of retries and a new reader mounts later
— the user navigates back to the screen — the reader starts a fresh fetch
with a fresh set of retries. `retryOnMount: false` leaves the error standing
instead, until something else asks. A query that failed a *refresh* still has
data, and the ordinary `refetchOnMount` rule decides for it.

## Never retried

- A `MissingQueryFunctionError` — there is no function to retry.
- A cancelled fetch — see [query cancellation](query-cancellation.md).

Retry policy, retry delay and network mode are read when a fetch starts; see
[when options are read](query-options.md#when-options-are-read).

An imperative `client.query` with no retry policy of its own or in the
defaults makes **one** attempt — there is no widget to show the error and try
again — and leaves the cache entry's existing policy in place for later
refetches; see [prefetching](prefetching.md#what-clientquery-joins).

## Tests

Three retries with backoff make a failing test wait seven seconds. Turn them
off in the client a test builds; see [testing](testing.md).

:::note[In React Query]
`retry` takes `false`, a number, `true` or a function; here
`RetryPolicy.never`, `times`, `always` and `when`. `retryDelay` takes
milliseconds or a function; here `RetryDelay.fixed`, `exponential` and
`dynamic`, with the same default numbers. A `MissingQueryFunctionError` is
retried like any failure there and never here. See
[differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
