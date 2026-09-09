# Changelog

## 0.1.0-dev

- A pure-Dart port of TanStack Query's `query-core` at upstream `50680b98c`:
  queries, mutations, infinite queries, their observers, the client and both
  caches. No Flutter dependency.
- Upstream's own test suite ported case for case (442 tests); every omission
  and every deliberate divergence is recorded in `test/PORTING_NOTES.md`.
- Dart-shaped API: sealed `QueryResult`, a `QueryKey` value type, sealed
  option values (`StaleTime`, `GcTime`, `Enabled`, `RetryPolicy`, `RefetchOn`,
  `RefetchInterval`), one `QueryClient.query` in place of `fetchQuery`,
  `prefetchQuery` and `ensureQueryData`, and per-client focus, online and
  notify managers.
- Not in this release: persistence and hydration, `useQueries`,
  `streamedQuery`, SSR. See the README's feature matrix.
