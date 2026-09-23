---
title: Side effects
description: Navigation, snackbars and analytics on a change of a result — QueryListener, InfiniteQueryListener and MutationListener, mutation callbacks, and the global callbacks for the whole app.
---

# Side effects

Some reactions to a result are not something to draw. A device was removed on
another phone, so its detail screen should close; a refresh failed, so a
snackbar should say so once; a rename was saved, so the sheet should go away.
Put any of those in `build` and it runs on every rebuild — the snackbar
appears three times, the navigator pops twice, and Flutter asserts because
you navigated in the middle of a frame.

A side effect belongs to a **change** in a result, not to a build. There are
three places for one, from the narrowest to the widest:

| Where | Runs for | Use it for |
|---|---|---|
| A listener widget | one controller, while that widget is mounted | navigation, a snackbar, anything that needs this screen's `context` |
| A mutation's callbacks | one mutation, or one call of it | writing the server's answer into the cache, invalidating |
| The caches' global callbacks | every query or mutation in the app | one error toast, logging, analytics |

## Listener widgets

`QueryListener`, `InfiniteQueryListener` and `MutationListener` run a
callback on a controller they **borrow** — the owner still disposes it — and
never rebuild their `child`. A device's detail screen that leaves when the
device is gone and says so when a refresh fails:

```dart snippet="guides/side-effects.md#device-screen"
class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late final QueryController<Device, Device> _device;

  @override
  void initState() {
    super.initState();
    _device = QueryController.create(
      QueryClientProvider.read(context),
      deviceQuery(widget.id),
    );
  }

  @override
  void didUpdateWidget(DeviceDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _device.setOptions(deviceQuery(widget.id));
  }

  @override
  void dispose() {
    _device.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return QueryListener<Device, Device>(
      controller: _device,
      // The moment it starts failing — not every notification while it stays
      // failed.
      listenWhen: (previous, next) =>
          previous is! QueryError && next is QueryError,
      listener: (context, result) {
        if (result case QueryError(error: ApiException(statusCode: 404))) {
          // Removed on another phone: nothing left to show here.
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not refresh this device')),
          );
        }
      },
      child: ValueListenableBuilder<QueryResult<Device>>(
        valueListenable: _device,
        builder: (context, device, _) => deviceTitle(device),
      ),
    );
  }
}
```

Two properties make these safe for navigation and snackbars, which is the
whole point of having them:

- **Nothing fires on mount** — only later transitions. Opening the screen on
  a query that already failed shows the error in the body, not a snackbar.
- **Callbacks are delivered off the build phase**, so a result that arrives
  mid-build reaches the listener after the frame, and `Navigator.pop` is
  safe.

`listenWhen` picks the transitions that matter. A rejected `listenWhen` still
advances the comparison state, so the next callback sees the transition it
actually followed. (That is the opposite of `buildWhen`, where `previous` is
what was last *built* — the two fields have genuinely different jobs.)

A listener takes a controller, whichever way the screen reads its data: the
controller shares the cache entry and the request with every other reader of
the same key, so a screen that draws with `context.query` or a builder can
own a controller for its listener alone. `context.mutation` and
`watchMutation` hand back a controller already, as below.

## Mutation callbacks

A mutation has callbacks of its own — `onMutate`, `onSuccess`, `onError`,
`onSettled` — on its options, and again on each call. The options' callbacks
are for what must happen whenever the write succeeds, wherever it was
started — keeping the cache right:

```dart snippet="guides/side-effects.md#rename-mutation"
MutationOptions<Device, String, void> renameDevice(
  QueryClient client,
  String id,
) =>
    MutationOptions.simple(
      mutationFn: (String name) => repository.rename(id, name),
      // The server's answer is the new detail: write it, no refetch needed.
      onSuccess: (device, _, __) {
        client.setQueryData(DeviceKeys.detail(id), device);
      },
    );
```

The screen's reaction — closing the sheet — is a listener on that mutation,
so it happens only while the sheet is there:

```dart snippet="guides/side-effects.md#rename-listener"
@override
Widget build(BuildContext context) {
  final rename = context.mutation(
    renameDevice(QueryClientProvider.of(context), id),
  );

  return MutationListener<Device, String, void>(
    controller: rename,
    listenWhen: (previous, next) => next is MutationSuccess,
    // Saved: the sheet has done its job.
    listener: (context, _) => Navigator.of(context).pop(),
    child: TextField(
      enabled: !rename.value.isPending,
      onSubmitted: rename.mutate,
    ),
  );
}
```

A per-call callback — `mutate(name, onSuccess: …)` — does the same for one
call, and is skipped once nothing listens to the mutation any more: when the
widget that made the call is gone by the time it settles. See
[mutations](mutations.md) for both, and [updates from mutation
responses](updates-from-mutation-responses.md) for what to write into the
cache.

## Global callbacks

For a side effect of *every* query or mutation — one error toast for the
whole app, a log line per failure — attach callbacks to the caches once,
where the client is built, and let each query's `meta` say whether it wants
the toast. See [global callbacks](global-callbacks.md).

The showcase's *global callbacks* screen wires both caches to a snackbar and
a log. Press *Fetch a missing post*: the query's own screen knows nothing
about it, yet a snackbar appears and the *Callback log* reads `query error
post-999 (meta: toast)`. On the mutation side, *Create todo* logs the
cache's callbacks and the options' callbacks in the order they run, and
*Create failing todo* logs `mutation error`:

<LiveDemo feature="global-callbacks" />

## Traps

- **A side effect in `build`.** It runs once per rebuild, and a rebuild is
  not a change. Move it into a listener.
- **A `listenWhen` that compares whole results.** Results differ on every
  fetch — `fetchStatus`, `dataUpdatedAt` — so `previous != next` fires for a
  refetch that changed nothing. Compare the part you react to, as the samples
  above do.
- **A cache write in a per-call `onSuccess`.** It is skipped when the user
  leaves the screen before the write settles, and the cache stays stale.
  Writes to the cache go in the options' callbacks.

:::note[In React Query]
TanStack Query removed `onSuccess`/`onError` from `useQuery` and points to
effects on `data` and `error`; the listener widgets are the Flutter-shaped
answer, shaped like bloc's `BlocListener`. The mutation callbacks and the caches'
global callbacks are the same as upstream's. See [differences from TanStack
Query](../reference/differences-from-tanstack.md).
:::
