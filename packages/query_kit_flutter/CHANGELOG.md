# Changelog

## 0.1.0

First release.

- The Flutter binding for `query_kit`: `QueryClientProvider`,
  listenable controllers (`QueryController`, `InfiniteQueryController`,
  `MutationController`), builder widgets (`QueryBuilder`,
  `InfiniteQueryBuilder`, `MutationBuilder`), the `QueryMixin` `State` mixin
  and the `context.query(...)` extension — four equal call styles.
- No dependency beyond Flutter; connectivity is opt-in through
  `QueryClientProvider.onlineStatus`, with `initialOnlineStatus` for what a
  `Stream` cannot say before its first event.
- Widget tests: the teardown a `QueryClient` needs — tear the tree down, let
  the frame after it run, `clear()`, let a dropped mutation's callbacks run,
  clear once more — is documented in the README and the testing guide as a
  snippet a suite wraps once; `flutter_test` is a dev dependency only, so
  nothing a test needs sits in an app's dependency graph.
- App lifecycle drives the client's focus state — `AppLifecycleState.inactive`
  read per platform, with `isAppShown` as the seam — and results that arrive
  mid-build are delivered after the frame.
- A widget builds once per changed result: an equal result rebuilds nothing,
  `buildWhen` on every builder decides the rest.
- `QueryClientProvider.maybeOf`; a controller's `value` before its first
  listener is the optimistic result, as a first build sees it.
- Requires Flutter 3.27 or later (tested on 3.27.4 and current stable).
