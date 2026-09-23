---
title: Global callbacks
description: QueryCache and MutationCache callbacks run for every query or mutation of a client — one error SnackBar for the whole app, a per-query opt-out through meta, and one invalidation rule for every write.
---

# Global callbacks

Some reactions belong to every query or every mutation: a SnackBar when a
background refresh fails, a log line for every failed write, an error report
to your crash service. Writing them into each widget repeats them and, worse,
runs them once per *reader* — ten widgets watching a failed query would show
ten SnackBars. Put them on the caches instead, once, when the client is
built:

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

## Reaching the UI from the cache

The client outlives every screen, and its callbacks run when a fetch
finishes, not while a widget builds — there is no `BuildContext` to hand
them. A `GlobalKey<ScaffoldMessengerState>` is the bridge: the app hands it to
`MaterialApp`, and the callback shows its SnackBar through it, over whatever
screen is up at that moment:

```dart snippet="guides/global-callbacks.md#wiring"
// lib/main.dart
class DevicesApp extends StatelessWidget {
  const DevicesApp({super.key, required this.client, required this.home});

  final QueryClient client;
  final Widget home;

  @override
  Widget build(BuildContext context) => QueryClientProvider(
        client: client,
        child: MaterialApp(
          // The key the cache's onError shows its SnackBar through.
          scaffoldMessengerKey: messengerKey,
          home: home,
        ),
      );
}
```

The same goes for a navigator key (to send the user to the sign-in screen on
a 401) or for your own notification service.

## What each cache offers

| | Callbacks |
|---|---|
| `QueryCache` | `onSuccess(data, query)`, `onError(error, stackTrace, query)`, `onSettled(data, error, stackTrace, query)` |
| `MutationCache` | `onMutate(variables, mutation)`, `onSuccess(data, variables, onMutateResult, mutation)`, `onError(error, stackTrace, variables, onMutateResult, mutation)`, `onSettled(data, error, stackTrace, variables, onMutateResult, mutation)` |

When they run:

- **Once per fetch**, not once per reader and not once per retry: ten widgets
  reading a query whose fetch failed after three attempts produce one
  `onError`. That is the difference from reacting in a widget — see [side
  effects](side-effects.md) for the per-reader form.
- **For fetches only.** A `setQueryData` is not a fetch and runs nothing, and
  neither does a cancelled fetch that reverts the query to where it was.
- **The cache's first.** A mutation's cache callback runs before the
  mutation's own callback of the same name, and the per-call callbacks passed
  to `mutate` run after both; see [mutations](mutations.md). A mutation
  cache callback may return a future, which is awaited: the mutation stays
  `pending` until it completes.

A query cache callback that throws does not change the fetch: the error is
reported to the zone, where your crash reporting sees it. On the mutation
side, a throw from `onMutate`, `onSuccess` or `onSettled` on the way to
success fails the mutation, as a throw from its own callbacks would; a throw
on the error path is reported to the zone and does not replace the error the
caller is waiting for.

## Opting out with `meta`

`meta` is any value — usually a map — on a query's or a mutation's options
that the library never reads. The global callbacks can, through `query.meta`
and `mutation.meta`, which makes it the way for one query to say "not me" to
a rule that holds for all the others. Above, a query with
`meta: {'silent': true}` fails without a SnackBar — a background poll of a
status light, say, whose failures the user does not need to hear about.

It works the other way round too: a rule that applies only to queries that
ask for it, such as `meta: {'toast': 'Could not load the energy chart'}`
carrying its own message.

## Invalidating after every mutation

When every write in an app follows the same rule — "invalidate the keys the
mutation names" — the rule can live in one place, the mutation cache's
`onSuccess`, and each mutation names its keys in `meta`:

```dart snippet="guides/global-callbacks.md#invalidate-by-meta"
QueryClient clientInvalidatingByMeta() {
  late final QueryClient client;
  client = QueryClient(
    mutationCache: MutationCache(
      onSuccess: (data, variables, onMutateResult, mutation) async {
        // A mutation names the keys it makes stale; the cache does the rest.
        if (mutation.meta case {'invalidates': final List<QueryKey> keys}) {
          await Future.wait(<Future<void>>[
            for (final key in keys)
              client.invalidateQueries(filters: QueryFilters(queryKey: key)),
          ]);
        }
      },
    ),
  );
  return client;
}

MutationOptions<Device, String, void> renameDevice(String id) =>
    MutationOptions.simple(
      mutationFn: (String name) => devices.rename(id, name),
      meta: <String, Object>{
        'invalidates': <QueryKey>[DeviceKeys.all],
      },
    );
```

Because the callback awaits the invalidation, each mutation stays `pending`
until the refetch has landed, as it would with the invalidation in its own
`onSuccess`. A mutation with no `invalidates` entry is left alone. The client
is `late` because the cache is built before the client it belongs to, and the
callback only runs after both exist.

## Seeing it

The `global-callbacks` screen runs on a client of its own whose caches log
every callback as one line. Press *Fetch a missing post*: the query fails,
the log shows `query error post-999 (meta: toast)`, and a SnackBar says *Post
not found* — the meta decided it. *Create todo* logs `mutation mutate`,
`mutation success`, `option onSuccess`, `mutation settled` and `option
onSettled`, in that order: the cache's callback before the option's, each
time.

<LiveDemo feature="global-callbacks" />

:::note[In React Query]
`new QueryCache({ onError, onSuccess, onSettled })` and
`new MutationCache({ ... })`, as there — the callbacks take the stack trace
as well here. TanStack Query v5 removed `onSuccess` and `onError` from
`useQuery`; this library never had them on a query, for the same reason: they
ran once per reader.
:::
