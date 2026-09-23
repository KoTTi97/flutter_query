---
title: Auth and token refresh
description: Refresh an expired token once for every request that hit it, never retry a refused request, and give each signed-in user a cache of their own.
---

# Auth and token refresh

An access token expires while the app is open. The next few requests come back
401 at once — the list, its details, a background refetch — and each of them
should wait for one refresh, then go again with the new token, without a
screen ever seeing the 401. A refresh that fails means the session is over.
Meanwhile the library's retry must not repeat a request the server refused,
and when a different user signs in, nothing the last one loaded may show up on
their screens. None of this belongs in a query function: the refresh sits in
the transport, and the cache boundary sits in the widget tree.

## The finished code

The tokens and the refresh call, on a `Dio` without the interceptor below:

```dart snippet="prose-only: needs dio, which neither published package may depend on" title="lib/data/token_store.dart"
import 'package:dio/dio.dart';

import '../app/signed_in_shell.dart'; // signedInUser

class TokenStore {
  TokenStore({required this.plainDio});

  /// A Dio without the interceptor below, for the refresh and for the
  /// repeated request: neither may run into the interceptor again.
  final Dio plainDio;

  String? accessToken;
  String? refreshToken;

  Future<void> refresh() async {
    final response = await plainDio.post<Map<String, Object?>>(
      '/auth/refresh',
      data: <String, Object?>{'refreshToken': refreshToken},
    );
    accessToken = response.data!['accessToken']! as String;
    refreshToken = response.data!['refreshToken']! as String;
  }

  void signOut() {
    accessToken = null;
    refreshToken = null;
    signedInUser.value = null;
  }
}
```

The interceptor that adds the token and handles a 401:

```dart snippet="prose-only: needs dio, which neither published package may depend on" title="lib/data/auth_interceptor.dart"
import 'package:dio/dio.dart';

import 'token_store.dart';

/// Adds the access token to every request, and on a 401 refreshes it once
/// and repeats the request. Queued: while one refresh runs, the other
/// requests that failed wait for it instead of refreshing again.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this._tokens);

  final TokenStore _tokens;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_tokens.accessToken case final token?) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Every path below ends in exactly one handler call: a queued
    // interceptor waits for it before it takes the next error.
    if (err.response?.statusCode != 401) return handler.next(err);
    final request = err.requestOptions;
    // Another request may have refreshed while this one waited its turn.
    if (request.headers['Authorization'] == 'Bearer ${_tokens.accessToken}') {
      try {
        await _tokens.refresh();
      } on Object catch (error) {
        // Refused, or an answer without tokens: the session is over. No
        // answer at all (no network) leaves the user signed in.
        if (error is! DioException || error.response != null) {
          _tokens.signOut();
        }
        return handler.next(err);
      }
    }
    final token = _tokens.accessToken;
    if (token == null) return handler.next(err); // signed out meanwhile
    request.headers['Authorization'] = 'Bearer $token';
    try {
      // The same options, so the same CancelToken: a query cancelled during
      // the refresh still aborts the repeat.
      handler.resolve(await _tokens.plainDio.fetch<Object?>(request));
    } on DioException catch (error) {
      handler.next(error);
    }
  }
}

Dio authenticatedDio(String baseUrl) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  final tokens = TokenStore(plainDio: Dio(BaseOptions(baseUrl: baseUrl)));
  dio.interceptors.add(AuthInterceptor(tokens));
  return dio;
}
```

Hand the result to the client from
[Wiring dio or package:http](wiring-dio-and-http.md):
`ApiClient(baseUrl: url, dio: authenticatedDio(url))`.

### Retry only what can succeed

```dart snippet="cookbook/auth-and-token-refresh.md#retry-policy" title="lib/app/retry.dart"
/// Retries what might succeed next time — a timeout, a 503 — and never a
/// refused login or a request the server called wrong.
const RetryPolicy retryTransientFailures = RetryPolicy.when(_isTransient);

bool _isTransient(int failureCount, Object error, StackTrace _) =>
    failureCount < 3 && !(error is ApiException && error.isClientError);
```

### A cache per signed-in user

```dart snippet="cookbook/auth-and-token-refresh.md#client-per-user" title="lib/app/signed_in_shell.dart"
/// Who is signed in: `null` while nobody is. Your auth layer owns this.
final ValueNotifier<String?> signedInUser = ValueNotifier<String?>(null);

class SignedInShell extends StatelessWidget {
  const SignedInShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
        valueListenable: signedInUser,
        builder: (context, userId, _) {
          if (userId == null) return const SignInScreen();
          // A new user is a new key, so a new client with an empty cache;
          // the old one is cleared once its subtree has gone.
          return QueryClientProvider.create(
            key: ValueKey<String>(userId),
            create: () => QueryClient(
              defaultOptions: const DefaultOptions(
                queries: QueryDefaults(retry: retryTransientFailures),
              ),
            ),
            child: child,
          );
        },
      );
}
```

## How it works

1. **The refresh happens below the library.** By the time a query function's
   future completes, the interceptor has refreshed and repeated the request.
   The query sees one slow success, not a failure and a retry, so no screen
   flashes an error and no error callback fires.
2. **`QueuedInterceptor` makes the refresh happen once.** Its `onError` calls
   run one after another: the next starts only when the one before has called
   `next` or `resolve`. The first 401 refreshes; the ones queued behind it
   find that their request went out with an older token than the store now
   holds, skip the refresh and repeat at once.
3. **The repeat goes out on the plain `Dio`.** Sent through the intercepted
   `Dio`, a repeat that failed again — a second 401, a 500, a cancel — would
   queue its error behind the `onError` that is waiting for it, and both would
   wait for ever, with every later error on that `Dio` queued behind them.
   On the plain `Dio` a failed repeat simply throws, and its error is passed
   on. That also makes a request repeat at most once: the repeat never meets
   this interceptor.
4. **A failed refresh ends the session, once.** A refresh the server refused
   (or answered without tokens) signs out and passes the original 401 on; it
   never starts another refresh. A refresh that got no answer — no network —
   passes the 401 on and leaves the user signed in.
5. **The repeat keeps its `CancelToken`.** `fetch(request)` sends the same
   `RequestOptions`, with the new token set by hand, so a query the library
   cancels during the refresh still aborts the repeated request. Other
   interceptors on the main `Dio` (logging, say) do not see the repeat; add
   them to the plain one too if they must.
6. **`retryTransientFailures` refuses 4xx.** The library's default retries a
   failed query three times with a growing delay, whatever the error. A 403 or
   a 404 will be a 403 or a 404 again; the policy returns `false` for any
   `ApiException` with a 4xx status and keeps the default three for the rest. It
   is a `const` built from a top-level function, so it can sit in
   `DefaultOptions` and compares equal from build to build.
7. **A new user is a new `QueryClient`.** `QueryClientProvider.create` owns the
   client it creates. Keyed by the user's id, a different user gives a new
   provider, so a new client with an empty cache; the old provider leaves the
   tree with everything below it, and the client it owned is cleared after it
   unmounts. The new user's screens never read the old user's client.

## Signing out without a new client

If one client lives for the whole app — created in `main`, say — clearing it
on sign-out is the equivalent, in a fixed order:

```dart snippet="cookbook/auth-and-token-refresh.md#sign-out-same-client" title="lib/app/sign_out.dart"
Future<void> signOutKeepingTheClient(QueryClient client) async {
  // 1. Leave the signed-in screens, so nothing reads a key any more …
  signedInUser.value = null;
  // … and let that frame run, so their observers are gone.
  await WidgetsBinding.instance.endOfFrame;
  // 2. Stop what is still in flight, then drop every entry and mutation.
  await client.cancelQueries();
  client.clear();
}
```

`clear()` empties the caches; it does not stop the observers reading them. A
screen still on the tree would find its entry gone and fetch it again — with
no token. So the signed-in screens go first, the frame that removes them runs,
and only then is the cache cleared.

A mutation that was still pending is dropped by `clear()`: a paused one fails
with a `CancelledError`, one whose request was already on its way settles with
that request's outcome, and either way its callbacks run a few microtasks
later. If that callback writes to the cache —
an optimistic update's rollback does — it re-creates the entry it names. Where
that matters, call `clear()` once more after the next frame.

## Traps

- **Do not refresh in a query function.** Catching a 401 there, refreshing and
  calling the API again works for one query and races for five: each refreshes,
  and all but one refresh with a token that the first has already rotated.
- **Do not retry a 401 through the library.** A retry is the same request with
  the same token after a delay. The interceptor is where a new token exists.
- **Do not put the user id in every key instead.** `['user', id, 'products']`
  keeps two users apart in one cache, but every key in the app has to remember
  it, and the old user's entries stay in memory until their `gcTime` runs out.
  A client per user gets both right by construction.
- **Paused mutations belong to the user who made them.** A mutation paused
  offline and then resumed after a sign-out would be sent with the next user's
  token. Clearing the client (or dropping it, as the keyed provider does)
  removes it.

## Variations

- **Sign-out from the interceptor.** `TokenStore.signOut` sets `signedInUser`
  to `null`, which takes `SignedInShell` back to the sign-in screen and drops
  the old client, from anywhere.
- **Several clients in one app.** A keyed provider can sit anywhere in the
  tree, not only at the root: an admin area that switches between tenants keys
  its provider by tenant the same way.

:::note[In React Query]
React Query has no opinion on auth either, and the same split applies: an axios
interceptor for the refresh, `retry` as a function for the policy, and
`queryClient.clear()` on sign-out. The keyed provider is the Flutter form of
remounting `QueryClientProvider` with a new client under a `key`.
:::

## See also

- [Query retries](../guides/query-retries.md) — `RetryPolicy`, its delays, and
  what the defaults are.
- [Mutations](../guides/mutations.md) — paused mutations and when they resume.
- [Reading queries in widgets](../guides/reading-queries-in-widgets.md) — how
  a widget finds its client.
