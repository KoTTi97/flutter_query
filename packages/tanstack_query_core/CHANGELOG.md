# Changelog

## 0.1.0-dev

- A pure-Dart port of TanStack Query's `query-core` at upstream `50680b98c`:
  queries, mutations, infinite queries, their observers, the client and both
  caches. No Flutter dependency.
- Upstream's own test suite ported case for case (467 tests, regressions from
  four external reviews included); every omission and every deliberate
  divergence is recorded in `test/PORTING_NOTES.md`.
- Dart-shaped API: sealed `QueryResult`, a `QueryKey` value type, sealed
  option values (`StaleTime`, `GcTime`, `Enabled`, `RetryPolicy`, `RefetchOn`,
  `RefetchInterval`), one `QueryClient.query` in place of `fetchQuery`,
  `prefetchQuery` and `ensureQueryData`, and per-client focus, online and
  notify managers.
- One key, one exact type: a covariant match (`int` under `int?`,
  `List<Sensor>` under `List<Object?>`) throws `QueryDataTypeError` instead of
  failing a cast deep inside; `getQueriesData` throws on a mismatch too.
- Timers are clamped to 2^31−1 ms, so a 30-day `gcTime` or refetch interval
  does not fire at once on the web.
- `InfiniteData` is structurally shared page by page; `InfiniteQueryOptions`
  carries its own paging behaviour, so `QueryClient.query` accepts it.
- `queryKey` is required on every options type; `MutationOptions.simple` for a
  mutation without an optimistic step; a `MissingQueryFunctionError` is never
  retried; the cache events' action and observer types are exported read-only.
- Not in this release: persistence and hydration, `useQueries`,
  `streamedQuery`, SSR. See the README's feature matrix.
