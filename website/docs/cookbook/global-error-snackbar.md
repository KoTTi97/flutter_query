---
title: A global error snackbar
description: One place that turns failed background refreshes and failed saves into a SnackBar — once per failure, never for what a screen already shows, and with a per-query way out.
---

# A global error snackbar

A list the user is reading refreshes in the background, and the refresh fails.
The list is still on screen and still correct as far as anyone knows, so the
screen shows it as before — but the user should hear that it may be out of
date. A save that fails behind a closed dialog should be reported too. Doing
that in every screen is repetitive and easy to forget; doing it in a query's
`queryFn` would report every retry. The caches take one `onError` each, which
runs once per failure after the retries are spent: the place for a single
toast. The work is in deciding what *not* to report.

## The finished code

What a query or a mutation can tell the handler, through `meta`:

```dart snippet="cookbook/global-error-snackbar.md#meta" title="lib/app/error_reporting.dart"
/// What a query or a mutation tells the app-wide error handler. The library
/// never reads `meta`; this app's handler does.
@immutable
class ErrorReporting {
  /// Toast failures, saying [message] instead of the generic sentence.
  const ErrorReporting.toast([this.message]) : show = true;

  const ErrorReporting._silent()
      : show = false,
        message = null;

  /// No toast: the screen shows this failure itself.
  static const ErrorReporting silent = ErrorReporting._silent();

  final bool show;
  final String? message;
}
```

The client, with a handler on each cache:

```dart snippet="cookbook/global-error-snackbar.md#client" title="lib/app/query_client.dart"
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

QueryClient createQueryClient() => QueryClient(
      queryCache: QueryCache(
        onError: (error, _, query) {
          // A first load has nothing on screen and shows its own error
          // state; a toast is for a refresh of data the user is looking at.
          if (!query.state.hasData) return;
          _toast(error, query.meta, fallback: 'Could not refresh');
        },
      ),
      mutationCache: MutationCache(
        onError: (error, _, __, ___, mutation) {
          // A form shows its field errors next to the fields.
          if (error is ValidationException) return;
          // A mutation with an `onError` of its own handles its failures.
          if (mutation.options.onError != null) return;
          _toast(error, mutation.meta, fallback: 'Could not save');
        },
      ),
    );

void _toast(Object error, Object? meta, {required String fallback}) {
  final reporting = meta is ErrorReporting ? meta : null;
  if (reporting?.show == false) return;
  final detail = error is ApiException ? error.message : 'Something went wrong';
  scaffoldMessengerKey.currentState
    // Ten queries failing together — the network went — say it once.
    ?..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text('${reporting?.message ?? fallback}: $detail')));
}
```

And the root widget, which hands the `MaterialApp` the messenger key:

```dart snippet="cookbook/global-error-snackbar.md#app" title="lib/app/app.dart"
class CatalogueApp extends StatelessWidget {
  const CatalogueApp({super.key, required this.api});

  final ProductApi api;

  @override
  Widget build(BuildContext context) => ProductApiScope(
        api: api,
        child: QueryClientProvider.create(
          create: createQueryClient,
          child: MaterialApp(
            scaffoldMessengerKey: scaffoldMessengerKey,
            home: const ProductListScreen(),
          ),
        ),
      );
}
```

## How it works

1. **The caches' `onError` runs once per failure.** `QueryCache.onError` is
   called when a query's fetch has failed for good — after its retries — and
   not for each attempt. A cancelled fetch — a search the next keystroke
   replaced, a first load its reader left — is not a failure and does not call
   it. `MutationCache.onError` is the same for a mutation.
2. **A toast needs no `BuildContext`.** The handler lives in the client, far
   from any widget. A `GlobalKey<ScaffoldMessengerState>` given to the
   `MaterialApp` reaches its messenger from anywhere, and `currentState` is
   `null` only before the app has built — then the toast is skipped.
3. **A first load is not toasted.** A query with no data has nothing on
   screen; its own error state is the report (the list screen's "Could not load
   products"). `query.state.hasData` tells the two cases apart.
4. **A form's field errors are not toasted.** A `ValidationException` is shown
   next to the fields by [the form](forms-and-server-validation.md), so the
   mutation handler skips it.
5. **A mutation with its own `onError` is not toasted.** The handler reads
   `mutation.options.onError`: if the mutation's options handle their failures,
   they know better than a generic sentence.
6. **`meta` is the per-query switch.** The library carries `meta` from the
   options to `query.meta` and `mutation.meta` and never reads it. This app
   reads it as an `ErrorReporting`: `toast('Could not refresh the catalogue')`
   changes the sentence, `ErrorReporting.silent` turns the toast off.
7. **Ten failures, one toast.** When the network goes, every active query
   fails at once. `hideCurrentSnackBar` before `showSnackBar` replaces the
   visible toast rather than queueing ten.

A query that reports its own failures opts out:

```dart snippet="cookbook/global-error-snackbar.md#opt-out" title="lib/features/products/product_queries.dart"
QueryObserverOptions<List<Product>> quietProductListQuery(ProductApi api) =>
    productListQuery(api).copyWith(meta: ErrorReporting.silent);
```

Try it: "Fetch a missing post" in the demo asks for a post that does not
exist, with a `meta` that asks for a toast; the cache's handler reads it and
shows the `SnackBar`. The log panel lists every cache callback as it runs.

<LiveDemo feature="global-callbacks" height={560} />

## Traps

- **Queries have no `onError` of their own.** Per-query `onSuccess`,
  `onError` and `onSettled` are not options; the cache-level callbacks replace
  them, and a screen reacts to a failure through the result it reads.
- **The callbacks are constructor arguments.** A `QueryCache` gets its
  `onError` when it is built, so the client has to be built with the caches —
  here in `createQueryClient`, handed to `QueryClientProvider.create`.
- **Pull-to-refresh reports twice.** A pulled refresh that fails gets a toast
  from here and a banner from the
  [pull-to-refresh screen](pull-to-refresh.md). Keep one: the screen's query
  can say `meta: ErrorReporting.silent`.
- **Offline is mostly a pause, not a failure.** In the default network mode a
  fetch that starts while the client believes it is offline pauses instead of
  failing, and a failed attempt waits for the network before its next retry.
  Going into a tunnel therefore does not produce a toast per query; only a
  fetch whose retries are spent fails, and is toasted once.
- **`meta` is typed `Object?`.** Anything can be there; the handler checks
  `meta is ErrorReporting` and treats anything else as "no preference".

## Variations

- **Report to a crash reporter.** The same handler is the place to send
  unexpected errors — not `ApiException`s — to your error-reporting service,
  with the query's key as context.
- **A success toast for mutations.** `MutationCache(onSuccess: ...)` with a
  `meta` that carries the sentence ("Saved") gives every mutation that asks
  for it the same confirmation.
- **Sign out on 401.** When auth is not handled in the transport, the query
  handler can check `error is ApiException && error.status == 401` and sign
  out; [Auth and token refresh](auth-and-token-refresh.md) handles it lower
  down instead.

:::note[In React Query]
The same pattern, and the same reasons: `new QueryCache({ onError })`, checking
`query.state.data !== undefined` before toasting, and `meta` to opt out. The
per-query `onError` was removed from `useQuery` in v5 for exactly this reason.
:::

## See also

- [Global callbacks](../guides/global-callbacks.md) — every cache-level
  callback and the order they run in.
- [Network mode](../guides/network-mode.md) — when a fetch pauses instead of
  failing.
- [Query retries](../guides/query-retries.md) — how long a failure takes to
  reach the handler.
