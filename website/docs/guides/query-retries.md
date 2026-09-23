---
title: Query retries
description: RetryPolicy and RetryDelay — three retries with exponential backoff by default, failureCount on the result, and what is never retried.
---

{/* depth: todo */}
{/* demo: retry */}

# Query retries

A query whose function throws is retried before the error reaches the screen:
three more times by default, waiting one second, then two, then four.

## `RetryPolicy`

| | |
|---|---|
| `RetryPolicy.times(n)` | retry up to `n` times after the first failure — `times(3)` is the query default |
| `RetryPolicy.never` | the first failure is the error — the mutation default |
| `RetryPolicy.always` | retry forever |
| `RetryPolicy.when((failureCount, error, stackTrace) => …)` | decide per failure; `failureCount` is `0` on the first decision |

`RetryPolicy.when` is where a policy tells errors apart — retry a timeout,
not a 404:

```dart snippet="guides/query-retries.md#retry-when"
const RetryPolicy retryUnlessNotFound = RetryPolicy.when(_retryUnlessNotFound);

bool _retryUnlessNotFound(int failureCount, Object error, StackTrace _) =>
    failureCount < 3 && !(error is HttpError && error.statusCode == 404);
```

`HttpError` stands for an exception type of your own that carries the status
code — see [query functions](query-functions.md). A top-level function keeps
the policy `const`, and one value on every build.

## `RetryDelay`

| | |
|---|---|
| `RetryDelay.exponential()` | the default: one second, doubling, capped at thirty; `base:` and `maximum:` change both |
| `RetryDelay.fixed(d)` | the same wait before every retry |
| `RetryDelay.dynamic((failureCount, error) => …)` | computed per failure |

## While it retries

The query stays `pending` (or keeps its data) and `fetching` while it
retries. The result carries `failureCount` and `failureReason`, so the UI can
say "attempt 2 of 4" without owning a counter. When the retries run out, the
result is a `QueryError`.

Offline, a query in the default [network mode](network-mode.md) pauses its
retries and continues when the client is online again.

## Never retried

- A `MissingQueryFunctionError` — there is no function to retry.
- A cancelled fetch — see [query cancellation](query-cancellation.md).

Retry policy, retry delay and network mode are read when a fetch starts; see
[when options are read](query-options.md#when-options-are-read).

An imperative `client.query` with no retry policy of its own or in the
defaults makes **one** attempt, and leaves the cache entry's existing policy
in place for later refetches; see [prefetching](prefetching.md#what-clientquery-joins).

## Tests

Three retries with backoff make a failing test wait seven seconds. Turn them
off in the client a test builds; see [testing](testing.md).
