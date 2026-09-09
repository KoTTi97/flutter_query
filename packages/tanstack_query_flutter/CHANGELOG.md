# Changelog

## 0.1.0-dev

- The Flutter binding for `tanstack_query_core`: `QueryClientProvider`,
  listenable controllers (`QueryController`, `InfiniteQueryController`,
  `MutationController`), builder widgets (`QueryBuilder`,
  `InfiniteQueryBuilder`, `MutationBuilder`), the `QueryMixin` `State` mixin
  and the `context.query(...)` extension — four equal call styles.
- No dependency beyond Flutter; connectivity is opt-in through
  `QueryClientProvider.onlineStatus`.
- App lifecycle drives the client's focus state, and results that arrive
  mid-build are delivered after the frame.
- Requires Flutter 3.27 or later.
