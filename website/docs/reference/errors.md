---
title: Errors
description: Every error query_kit and query_kit_flutter throw or record, every debug-build check you can trip, and what to do about each.
---

# Errors

Errors reach you in three ways, and which one decides where you handle it:

- **Thrown synchronously** from the call you made — a cache read with the
  wrong type, an option combination that cannot work, a widget without a
  provider. These are programming errors: fix the call.
- **Recorded as a fetch or mutation error** — in the result's `error`, in
  the cache's `onError` hook, and thrown from `client.query` or
  `mutateAsync`. These go through the retry policy unless the table says
  otherwise.
- **Reported to the zone** — a callback or listener that throws. Nothing
  around it is interrupted; the error goes to the zone's error handler, which
  in Flutter is `FlutterError.onError` or `PlatformDispatcher.onError`.

Debug-build checks (asserts and debug-only `FlutterError`s) are listed at the
end. They cost nothing in a release build — and do not protect you there
either.

A TanStack Query name is given only where it differs from the Dart one.

For symptoms rather than error names, see [troubleshooting](troubleshooting.md).
The [debugging guide](../guides/debugging.md) shows how to watch errors as
they happen.

## Exported error types

| Type | Package | Carries |
|---|---|---|
| [`QueryDataTypeError`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryDataTypeError-class.html) | `query_kit` | `queryKey` (`QueryKey?`), `expected` (`Type`), `actual` (`Type`). No TanStack counterpart. |
| [`MissingQueryFunctionError`](https://pub.dev/documentation/query_kit/latest/query_kit/MissingQueryFunctionError-class.html) | `query_kit` | `queryKey` (`QueryKey`). TanStack: a plain `Error` with a message. |
| [`MissingMutationFunctionError`](https://pub.dev/documentation/query_kit/latest/query_kit/MissingMutationFunctionError-class.html) | `query_kit` | `mutationKey` (`QueryKey?`). TanStack: a plain `Error` with a message. |
| [`CancelledError`](https://pub.dev/documentation/query_kit/latest/query_kit/CancelledError-class.html) | `query_kit` | `revert` (`bool`, default `false`), `silent` (`bool`, default `false`) |

All four implement `Exception`, so `on Exception catch` sees them and an
`Error`-only handler does not. The binding exports no error type of its own:
it throws Flutter's `FlutterError` with a message that names the call and the
fix.

## `QueryDataTypeError`

One key holds one exact data type. A read or write that names another type —
a subtype, a supertype, or the non-nullable form of a nullable one — throws
`QueryDataTypeError` instead of casting. See
[one key, one exact type](../dart-type-safety.md#one-key-one-exact-type).

**Thrown synchronously from:**

| Call | When |
|---|---|
| `QueryCache.get`, `client.getQueryData`, `getInfiniteQueryData`, `getQueryState` | The type argument differs from the type the entry holds. |
| `client.getQueriesData` | Any matching entry holds another type. |
| `client.setQueryData` | The value is not something the entry's own type can hold. An inferred type argument alone does not throw: an entry of `List<Todo>?` takes a `List<Todo>`. |
| `client.updateQueryData` | The entry holds data that is not a `TQueryData`, so the updater cannot be handed it, or the updater returns a value the entry's own type cannot hold. |
| `client.updateQueriesData` | The same, for any matching entry. Every updater runs before anything is written, so a throw writes nothing. |
| `client.query`, `client.infiniteQuery` | The key's entry holds another type. Thrown before any future exists, so it is not a rejected future. |
| `QueryObserver` constructor, `setOptions`, `getOptimisticResult` | The options' type does not match the entry. This is what surfaces from `context.query`, `QueryController` and the other binding reads. |

**Recorded as a fetch or mutation error** when a default registered for many
keys returns a value of the wrong type:

| Source | `queryKey` | Retried |
|---|---|---|
| a `queryFn` from `setQueryDefaults` | the key | yes, per the query's `retry` |
| a `structuralSharing` hook from the defaults | `null` | no — it fails after the data arrived |
| a `mutationFn` from `setMutationDefaults` | `null` | per the mutation's `retry`, which defaults to never |

**Fix.** Use one type per key, or name the type argument. When `actual` is
the nullable form of `expected`, the message says so and names the type
argument to write: an entry of `String?` read as `getQueryData<String>(…)`
wants `getQueryData<String?>(…)`. A default that serves many keys with
different types should check the key, or be split into several defaults.

## `MissingQueryFunctionError`

A fetch started for a query that has no `queryFn` in its options and none
registered with `setQueryDefaults` for its key. Typical causes: a
`client.query` with options that were only meant to read, or a refetch of a
key whose data was only ever written with `setQueryData`.

It is the fetch's error: the query goes to `error`, the cache's `onError`
runs, and `client.query` rejects with it. It is **never retried** — no
number of attempts will produce a function. TanStack Query retries it like
any other failure.

**Fix.** Give the options a `queryFn`, or register one for the key prefix
with `client.setQueryDefaults`. See the
[default query function](../guides/default-query-function.md) guide.

## `MissingMutationFunctionError`

A mutation ran with neither `mutationFn` nor `mutationFnWithContext` set and
no default registered for its key with `setMutationDefaults`. `mutationKey`
is `null` for an unkeyed mutation.

It is the mutation's error and is **never retried**. Nothing is sent. The
error callbacks run — the cache's, the options', then the per-call ones — the
result shows `status: error`, and `mutateAsync` throws it.

**Fix.** Give the options a `mutationFn`, or register one with
`client.setMutationDefaults` for the mutation's key.

Both type errors and a missing mutation function can be tried in the
diagnostics screen below. "Read as int" reads the counter with its own type;
"Read as String" reads it as the wrong type and shows the
`QueryDataTypeError`; "Write a String" tries to write the wrong type and
leaves the entry unchanged; "Mutate without a function" fails with
`MissingMutationFunctionError` and sends nothing; after "Register a default
mutationFn", the same mutation succeeds.

<LiveDemo feature="diagnostics" />

## `CancelledError`

A fetch or mutation that was stopped fails with `CancelledError`. Its two
flags say what the cancel asked for, and whether you see it at all depends on
them.

| Where it comes from | `revert` / `silent` | What you see | Retried |
|---|---|---|---|
| `client.cancelQueries` (default `revert: true`) | `true` / `false` | The state goes back to what it was before the fetch; no error is recorded and `onError` does not run. A caller awaiting the fetch gets the data the query held, or the `CancelledError` when it held none. | no |
| `Query.cancel()`, or `cancelQueries(revert: false)` | `false` / `false` | Recorded as the query's error; the cache's `onError` and `onSettled` run with it. | no |
| a new fetch with `cancelRefetch` over a running one | `false` / `true` | Nothing: the callers of the cancelled fetch ride on the new one. | no |
| the last observer leaving while the query function used its signal, or while a first fetch is paused | `true` / `false` | As with `cancelQueries`: the state is put back. | no |
| `Query.fetch` on a query already removed from the cache | `false` / `true` | The returned future fails with it; the query's state is untouched. | no |
| `Mutation.cancel`, `MutationObserver.cancel`, `MutationController.cancel` | `false` / `false` | The mutation fails with it: `status: error`, `onError` and `onSettled` run, `mutateAsync` throws it. Nothing is reverted — undo optimistic updates in `onError`. | no |
| a paused mutation removed from the cache, or the cache cleared | `false` / `false` | The mutation fails with it. | no |

A cancellation never counts toward `consecutiveErrorCount`.

A `CancelledError` the query function throws **for its own reasons** — from
some other token — is an ordinary failure and is retried like any other. One
thrown by `QueryCancelToken.throwIfCancelled` after its own signal was
cancelled changes nothing: the fetch had already ended when the signal fired.

**Fix.** Usually none: handle it as "not an error" where you display errors,
by testing `error is CancelledError`. See
[query cancellation](../guides/query-cancellation.md) and
[cancelling mutations](../guides/cancelling-mutations.md).

## Other errors from `query_kit`

These are Dart's own error types, thrown synchronously from a call whose
arguments cannot work. None of them is retried; none reaches a result.

| Error | Thrown by | When | Fix |
|---|---|---|---|
| `ArgumentError` | `QueryObserver` constructor, `setOptions`, `getOptimisticResult` | No `select`, and the cached type is not the reported type. | Add a `select`, or make the two types the same. |
| `ArgumentError` | `QueriesObserver` constructor, `setQueries` | "QueriesObserver requires select when data types differ." A throwing `setQueries` leaves the list as it was, except that members before the failing entry keep their new options. | Give every entry whose types differ a `select`. |
| `ArgumentError` | `client.defaultQueryOptions`, and so every query read | Both `initialDataUpdatedAt` and `initialDataUpdatedAtCompute` are set. | Set one. |
| `ArgumentError` | `client.defaultMutationOptions`, and so `MutationObserver` and every mutation | Both `mutationFn` and `mutationFnWithContext` are set, counting defaults. The `MutationOptions` constructor also asserts it in debug builds. | Set one. |
| `ArgumentError` | `QueryCache.build(state:)`, `Query.setState` | The state is inconsistent — `success` without data, say. | Build the state with the constructors `QueryState` offers, or restore what was saved unchanged. |
| `ArgumentError` | `MutationCache.build(state:)` | A `pending` state without variables (where `null` is not a valid variables value), or a `success` state without data. | As above, for `MutationState`. |
| `StateError` | `QueryCache.add`, `MutationCache.add` | The entry was removed from its cache before. | Build a new entry; a removed one cannot come back. |
| `ArgumentError` | `InfiniteData` constructor | `pages` and `pageParams` differ in length. | Keep them paired. |
| `ArgumentError` | `InfiniteData.flatten<T>` | A page is not an `Iterable<T>`. | Name the element type the pages really hold, or flatten with your own `expand`. |
| `ArgumentError` | `copyWith` on `InfiniteQueryOptions`, `InfiniteQueryObserverOptions`, `InfiniteQuerySelectOptions` | `queryFn:` passed — an infinite query's function is `pageFn`. On the two observer option types, also `pages:` — an observer refetches as many pages as the query holds. | Change `pageFn`; pass a page count to `client.infiniteQuery` instead. |
| `UnsupportedError` | `InfiniteQueryObserver.setOptions`, `getOptimisticResult` | Plain observer options were passed. | Use `setInfiniteOptions` with options from `client.infiniteObserverOptions`. |
| `ArgumentError` | `AppFocusManager` constructor | `refetchMinBackgroundDuration` is negative. | Pass zero or more. |

## Errors from callbacks and listeners

What happens when your own code throws depends on where it runs.

**Reported to the zone, outcome unchanged:**

- a `QueryCache` or `MutationCache` listener (`subscribe`);
- an observer or controller listener;
- a `QueryCache` hook — `onSuccess`, `onError`, `onSettled`;
- a mutation's `onError` or `onSettled` after a failure, from the cache or the
  options;
- a per-call `MutateCallbacks` callback;
- a callback registered with a cancel token's `onCancel`;
- a callback queued on the `NotifyManager`;
- in the binding, the callbacks of `QueryListener`, `InfiniteQueryListener`
  and `MutationListener` — these go to `FlutterError.reportError`, which
  calls `FlutterError.onError`, rather than to the zone.

**Change the outcome:**

- a mutation's `onMutate` (cache or options) that throws fails the mutation
  with that error; the mutation function never runs;
- a mutation's `onSuccess`, or `onSettled` after a success, that throws
  turns the run into an error with that error.

See [global callbacks](../guides/global-callbacks.md) for where each hook
runs.

## Errors from `query_kit_flutter`

| Error | Build modes | When | Fix |
|---|---|---|---|
| [`QueryClientProvider.of`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryClientProvider/of.html), `.read`: `FlutterError` "No QueryClientProvider found above this widget…" | all | No `QueryClientProvider` above the context. | Put one above the widget, or pass `client:` to the builder or controller. `QueryClientProvider.maybeOf` returns `null` instead of throwing. |
| `context.query`, `selectQuery`, `infiniteQuery`, `mutation`: `FlutterError` | all | The same, with a message that names `context.query()` whichever of these was called. `QueryMixin` reads and builders without `client:` throw through `of`. | As above. |
| `QueryClientProvider`: `FlutterError` "QueryClientProvider could not listen to its onlineStatus" | all | `onlineStatus` is a single-subscription stream and a second provider, or a replaced one, listened to it again. | Pass `stream.asBroadcastStream()`. |
| `onlineStatus` stream errors | all | The stream emits an error, or cancelling it throws. Reported through `FlutterError.reportError`, not thrown; the online state is unchanged. | Handle errors in the stream. |

## Debug-build checks

These run only in debug builds. In a release build the same code runs on
without the check, with the behaviour described.

| Check | Raised by | When | Release behaviour | Fix |
|---|---|---|---|---|
| `FlutterError` "… was called with the context an item builder was given." | `context.query` and the other context reads | The context is one a `ListView.builder`, `GridView.builder`, `PageView.builder`, `SliverList` builder, `ListWheelScrollView` or two-dimensional scroll view handed to its item builder. `selectQuery` reports as `context.query`. | The read is kept until the list's parent rebuilds or the list unmounts, so rows scrolled away keep their queries alive. | Make the row its own widget and read in its `build`. |
| `FlutterError` "This widget read the query … twice in one build with options that produce different results" (or "This State …") | `context.query`, `selectQuery`, `infiniteQuery`; `watchQuery`, `watchSelectQuery`, `watchInfiniteQuery` | One build reads the same key twice with options that would give different results — two `select`s, say. | The two reads share one reader, and the later options win. | Pass a distinct `id:` to each read. |
| `FlutterError` for two different mutations | `context.mutation`, `watchMutation` | Two reads without `id` in the reader's own build differ in the function, a callback, `scope`, `retry`, `retryDelay`, `networkMode` or `gcTime`. `meta` is not compared; `RetryPolicy.when` and `RetryDelay.dynamic` are compared by kind only. | Both reads share one mutation observer with the later options. | Pass a distinct `id:` to each read. |
| `AssertionError` on a top type | `QueryController`, `InfiniteQueryController`, `QueryController.observing` | The data type is `dynamic` or `Object?` — usually an inferred type argument. | The controller works, untyped. | Name the data type. |
| `AssertionError` on the mutation function | `MutationOptions` | Both `mutationFn` and `mutationFnWithContext` are set. Resolving the options throws `ArgumentError` in every mode. | `ArgumentError` when the options are resolved. | Set one. |
| `AssertionError` on a key part | `QueryKey` | A part of the key has no value equality — a class without `==` and `hashCode`, a closure — or a map in it is keyed by a collection. | The key compares by identity and a new instance per build misses the cache. | Use strings, numbers, records, lists, maps, or classes with value equality. See [query keys](../guides/query-keys.md). |

## How this differs from TanStack Query

- A missing query function is never retried; TanStack Query retries it.
- The cache's `onError` takes the stack trace as its second argument.
- Reading or writing a key with the wrong type throws `QueryDataTypeError`;
  TypeScript's types vanish at runtime and nothing checks there.
- A mutation can be cancelled, and fails with `CancelledError`; TanStack
  Query has no mutation cancel.

The full list is in
[differences from TanStack Query](/docs/reference/differences-from-tanstack).
