---
title: Global callbacks
description: QueryCache and MutationCache callbacks run for every query or mutation of a client — one error toast for the whole app, with a per-query opt-out through meta.
---

{/* depth: todo */}
{/* demo: global-callbacks */}

# Global callbacks

Some reactions belong to every query or every mutation: a toast when a
background refresh fails, a log line for every failed write. Put them on the
caches, once, when the client is built:

```dart snippet="guides/global-callbacks.md#error-toasts"
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

QueryClient clientWithErrorToasts() => QueryClient(
      queryCache: QueryCache(
        onError: (error, stackTrace, query) {
          // A first load shows its own error; only a failed background
          // refresh of data already on screen deserves a toast.
          if (!query.state.hasData) return;
          // A query can opt out through its meta.
          if (query.meta case {'silent': true}) return;
          messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Could not refresh: $error')),
          );
        },
      ),
      mutationCache: MutationCache(
        onError: (error, stackTrace, variables, onMutateResult, mutation) {
          messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Could not save: $error')),
          );
        },
      ),
    );
```

Hand `messengerKey` to `MaterialApp(scaffoldMessengerKey: …)`. The client
outlives any one screen, so a global key — not a `BuildContext` — is how it
reaches the UI.

## What each cache offers

| | Callbacks |
|---|---|
| `QueryCache` | `onSuccess(data, query)`, `onError(error, stackTrace, query)`, `onSettled(data, error, stackTrace, query)` |
| `MutationCache` | `onMutate`, `onSuccess`, `onError(error, stackTrace, variables, onMutateResult, mutation)`, `onSettled` |

They run **once per fetch or mutation run**, not once per reader: ten widgets
reading a failed query produce one `onError`. That is the difference from
reacting in a widget — see [side effects](side-effects.md) for the per-reader
form.

A mutation's own callbacks run after the cache's, and the per-call callbacks
passed to `mutate` after both; see [mutations](mutations.md).

## Opting out with `meta`

`meta` is any value — usually a map — on a query's or a mutation's options that the library never
reads. A global callback can: above, a query with `meta: {'silent': true}`
fails without a toast.
