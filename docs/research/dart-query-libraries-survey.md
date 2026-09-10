# Survey: how existing Dart/Flutter query libraries shape their API, and what users complain about

- **Date:** 2026-09-08
- **Ticket:** https://github.com/KoTTi97/flutter_query/issues/3
- **Purpose:** input for the binding-shape decision. The port's `query_core` is
  done; the open question is what the *Flutter-facing* API should look like to
  be the best Flutter-world result rather than the closest translation.

## Method and scope

Primary sources only: pub.dev package JSON (`https://pub.dev/api/packages/<name>`)
and score JSON (`https://pub.dev/api/packages/<name>/score`), the packages'
GitHub repositories (README, CHANGELOG, source tree, full issue list via the
GitHub API), the packages' own documentation sites, and riverpod.dev. All
numbers were read on 2026-09-08. Downloads are pub.dev's 30-day counter.

Packages were found by searching pub.dev for `tanstack`, `react query`, `swr`
and `query cache server state` (`https://pub.dev/api/search?q=...`). The five
required subjects get full sections; the long tail of small TanStack-inspired
packages is summarised in §5 because it shows what people keep rebuilding.

### Snapshot

| Package | Latest (date) | Pub points | Likes | DL/30d | GitHub stars | Open issues | Last push | Consumption idiom | Result typing | Hooks dep? |
|---|---|---|---|---|---|---|---|---|---|---|
| `fquery` | 3.1.0 (2026-06-25) | 155/160 | 88 | 1,678 | 163 | 3 | 2026-07-12 | `QueryBuilder` widgets **and** `useQuery` hooks | bool flags + `status` enum, `data!` | yes (hard) |
| `cached_query` / `cached_query_flutter` | 3.7.0 / 3.4.0 (2026-05-17) | 160 / 160 | 101 / 38 | 13,526 / 8,788 | 88 | 7 | 2026-08-17 | `Query` object + `stream`; `QueryBuilder(query:)` | sealed `QueryStatus<T>` + bool getters | no |
| `flutter_query` (jezsung) | 0.11.1 (2026-07-14) | 160/160 | 38 | 268 | 32 | 3 | 2026-07-14 | hooks only (`useQuery` in `HookWidget`) | bool flags + `status` enum, `data!` | yes (hard) |
| `tanstack_query` (Phenek) | 1.2.7 (2026-04-15) | 140/160 | 7 | 42 | 3 | 0 | 2026-05-19 | hooks only | bool flags (`isPending`), `data ?? []` | yes (hard) |
| `riverpod` / `flutter_riverpod` | 3.4.3 (2026-09-03) | 160 / 140 | 4,028 / 2,906 | 3.02M / 2.95M | 7,378 | 154 | 2026-09-08 | top-level providers, `ref.watch` in `ConsumerWidget` | sealed `AsyncValue<T>` + extension flags | optional (`hooks_riverpod`) |

Sources: pub.dev API/score endpoints for each package
(e.g. https://pub.dev/api/packages/fquery, https://pub.dev/api/packages/fquery/score),
and the GitHub repository API for https://github.com/41y08h/fquery,
https://github.com/D-James-GH/cached_query, https://github.com/jezsung/query,
https://github.com/Phenek/flutter_tanstack_query, https://github.com/rrousselGit/riverpod.

---

## 1. `fquery` (+ `fquery_core`)

### Identity and status
- pub.dev: 3.1.0 published 2026-06-25; 25 versions since `1.0.0-beta.1` on
  2022-07-02; 155/160 points, 88 likes, 1,678 downloads/30d; SDK `flutter` only;
  depends on `flutter_hooks`, `freezed`, `collection`, `fquery_core`
  (https://pub.dev/api/packages/fquery, https://pub.dev/packages/fquery/score).
- GitHub `41y08h/fquery`: 163 stars, 19 forks, 3 open issues, last push
  2026-07-12, MIT, default branch `dev` (https://github.com/41y08h/fquery).
- Single maintainer. The maintainer stated in May 2025 that "serious health
  issues" had slowed the project and that the package was still in beta only
  because internal tests were missing
  (https://github.com/41y08h/fquery/issues/48).
- Three incompatible generations: `1.x-beta` (hooks-first), `2.0.0`
  (2025-09; fixes #46/#47 "resolved in v2.0.0"), `3.0.0` (core moved to
  `fquery_core`; `QueryClient` removed and folded into `QueryCache`;
  `QueryClientProvider` renamed `CacheProvider`)
  (https://github.com/41y08h/fquery/blob/dev/packages/fquery/CHANGELOG.md).

### Declaring and consuming a query
- Widget form: `QueryBuilder<List<Todo>, Exception>(options: QueryOptions(queryKey: QueryKey(['todos']), queryFn: ...), builder: (context, todos) { if (todos.isLoading) ...; if (todos.isError) ...; todos.data! })`
  (https://github.com/41y08h/fquery/blob/dev/packages/fquery/README.md).
- Hook form: `useQuery<TData, TError extends Exception>(RawQueryKey queryKey, QueryFn<TData> queryFn, {required BuildContext context, bool enabled, RefetchOnMount?, Duration? staleDuration, cacheDuration, refetchInterval, int? retryCount, Duration? retryDelay})`
  — note the `context:` parameter is required so the hook can find the cache
  (https://github.com/41y08h/fquery/blob/dev/packages/fquery/lib/src/hooks/use_query.dart).
- Also `InfiniteQueryBuilder`/`useInfiniteQuery`, `QueriesBuilder`/`useQueries`
  (dynamic parallel queries), `IsFetchingBuilder`/`useIsFetching`, and
  non-reactive readers `QueryInstance.of(context, options)` for calling
  `fetchNextPage` from a scroll listener (README, "Reading queries outside of
  builder").
- Builder widgets were added in `1.2.0-beta.1` explicitly so the package "can be
  used without extending the widget with `HookWidget`" (CHANGELOG).

### Providing the client/cache
- `CacheProvider(cache: QueryCache(defaultQueryOptions: DefaultQueryOptions(...)), child: ...)`;
  read with `CacheProvider.of(context)` / `CacheProvider.get(context)` (README).
- Issue #46 complained that the pre-3.0 `QueryClientProvider.of(context)`
  returned the provider widget, not the client, and asked for `QueryClient.of(context)`
  in the `Theme.of` style (https://github.com/41y08h/fquery/issues/46).

### Result typing
- `QueryResult` is a flat record of booleans and nullable fields: `data`,
  `error`, `isError`, `isLoading`, `isFetching`, `isSuccess`, `status`,
  `refetch`, `isInvalidated`, `isRefetchError`, `dataUpdatedAt`,
  `errorUpdatedAt` (use_query.dart, return statement). Consumers write
  `todos.data!` after checking flags (README).
- `isInvalidated`/`isRefetchError` were added on request (#27) after a user
  needed to distinguish "refetching because a mutation invalidated me" from
  "polling"; the maintainer resisted exposing the whole `QueryState`
  (https://github.com/41y08h/fquery/issues/27).

### Mutations
- `MutationBuilder<TData, TError, TVariables, TContext>(mutationFn, onMutate:, onError:, onSuccess:, onSettled:, builder: (context, mutation) ...)`
  and `useMutation`. Optimistic updates are hand-rolled: `onMutate` snapshots
  via `cache.getQueryData`, writes via `cache.setQueryData`, returns the
  snapshot as `TContext`; `onError` restores it (README, "MutationBuilder").
- `mutateAsync` returning `Future<TData>` was requested and closed (#59)
  (https://github.com/41y08h/fquery/issues/59).

### Keys
- `QueryKey(List)` wrapping a raw list; deep equality only since
  `1.5.4-beta.1` after #44 reported that `['posts', {'search': 'trees'}]` was
  never a cache hit. The changelog adds "Query keys must be serializable"
  (https://github.com/41y08h/fquery/issues/44,
  https://github.com/41y08h/fquery/blob/dev/packages/fquery/CHANGELOG.md).
- Prefix invalidation `cache.invalidateQueries(['posts'])`, `exact: true` for
  exact match (README).

### TanStack feature claims
- Claimed: caching + GC (`cacheDuration`), staleness (`staleDuration`),
  `refetchInterval`, `refetchOnMount` enum (`always`/`stale`/`never`),
  `retryCount`/`retryDelay`, `enabled` (dependent queries), infinite queries
  with `initialPageParam`/`getNextPageParam`/`getPreviousPageParam`, parallel
  queries, invalidation, manual `setQueryData`, mutations with optimistic
  updates (README "Features" and option docs).
- Not offered: refetch on focus/resume (asked in #38, answered "already planned" in 2025-03, not shipped), refetch on reconnect,
  persistence (#36 open since 2024-09, "It's coming soon" 2025-03), `select`,
  `placeholderData`/`keepPreviousData`, cancellation.
- Dedup is implicit: observers with the same key share one `Query` in the
  cache (README "Query invalidation" describes shared queries; `use_query.dart`
  looks up `cache.queries[QueryKey(queryKey)]`).

### Testing
- Sparse: `packages/fquery/test/hooks/` has two files (`use_query_test.dart`
  3.2 KB, `use_infinite_query_test.dart` 4.0 KB), `test/src/` has two observable
  tests, `packages/fquery_core/test/` has `gc_test.dart` and a `repro.dart`
  (GitHub contents API on branch `dev`).
- No testing guide; #48 "Documents about testing" is open
  (https://github.com/41y08h/fquery/issues/48). Pending-`Timer` failures in
  tests were a bug (#35, fixed 1.5.2-beta.1).

### Recurring complaints (issue tracker)
- **Framework re-entrancy crashes**: "setState() or markNeedsBuild() called
  during build" when two screens use the same `useQuery` (#6, reopened once,
  fixed 1.3.2-beta.2); "called when widget tree was locked" during dispose,
  regression in 3.0.1, still open (#57)
  (https://github.com/41y08h/fquery/issues/6,
  https://github.com/41y08h/fquery/issues/57).
- **Silent type failures**: a `catch (e)` swallowed
  `type 'Query<Post, dynamic>' is not a subtype of 'Query<Post, Exception>'`,
  so priming the cache produced a spurious loading state and refetch (#47)
  (https://github.com/41y08h/fquery/issues/47).
- **Invalidation not refetching** (#25, #50), **query function called twice**
  (#41), **widget rebuilds twice** (#39), **`retryCount: 0` ignored** (#40),
  **infinite-query refetch semantics** (#49, #60, #61).
- **Ergonomics**: cumbersome client access (#46), `QueryKey` not exported (#44
  comment), wants `isInvalidated`/whole state (#27), wants storage (#36),
  wants testing docs (#48).
- A user proposed merging with `cached_query` because the goals overlap (#37)
  (https://github.com/41y08h/fquery/issues/37).

---

## 2. `cached_query` + `cached_query_flutter` (+ `cached_storage`, devtools)

### Identity and status
- pub.dev `cached_query`: 3.7.0 on 2026-05-17; 77 versions since 0.0.1
  (2022-06-26); 160/160, 101 likes, 13,526 downloads/30d; SDK `dart` **and**
  `flutter`; deps `rxdart`, `meta`
  (https://pub.dev/api/packages/cached_query,
  https://pub.dev/packages/cached_query/score).
- pub.dev `cached_query_flutter`: 3.4.0 on 2026-05-17; 160/160, 38 likes,
  8,788 downloads/30d; deps `flutter`, `cached_query`, `connectivity_plus`
  (https://pub.dev/api/packages/cached_query_flutter).
- GitHub `D-James-GH/cached_query` (monorepo with `cached_storage` and
  `devtools_extension`): 88 stars, 19 forks, 7 open issues, last push
  2026-08-17, created 2021-09-20, MIT. Docs at https://cachedquery.dev.
- Single maintainer; the most-downloaded dedicated query library in Dart by a
  wide margin (see snapshot table). Self-described as "inspired by tools such
  as SWR, RTKQuery, React Query, Urql and apollo"
  (https://github.com/D-James-GH/cached_query/blob/main/packages/cached_query/README.md).

### Declaring and consuming a query
- A query is an **object**: `Query<T>(key: ..., queryFn: ..., config: QueryConfig(...))`.
  Consume by `await query.result` (one-shot) or `query.stream`
  (`Stream<QueryStatus<T>>`) — the README recommends the stream. Same key ⇒
  same cached instance, so a `Query(...)` factory can be called freely
  (README "Getting started"; https://github.com/D-James-GH/cached_query/issues/99).
- Flutter: `QueryBuilder<QueryStatus<T>>(query: Query(...), builder: (context, state) ...)`,
  plus `QueryListener`, `QueryConsumer`, `MutationBuilder`, `MutationListener`,
  `MutationConsumer` (bloc-style triad; `packages/cached_query_flutter/lib/src`
  listing). `InfiniteQuery<T, Arg>(key:, getNextArg: (state) => ..., queryFn: (arg) => ...)`.
- Explicitly positioned to sit under Bloc/Provider: "Can be used alongside
  state management options"; docs show `emit.forEach(query.stream, ...)` in a
  bloc (`cached_query_flutter` README, "With the bloc pattern").

### Providing the client/cache
- A **singleton** configured once: `CachedQuery.instance.config(storage:, config: GlobalQueryConfig(staleDuration:, cacheDuration:))`
  or `configFlutter(config: GlobalQueryConfigFlutter(refetchOnConnection:, refetchOnResume:))`
  (READMEs). No `InheritedWidget`; queries find the cache by global.
- Multiple instances were requested (#42) and added (`CachedQuery.asNewInstance()`,
  `cache:` parameter on queries; #100 reports a bug with it)
  (https://github.com/D-James-GH/cached_query/issues/42,
  https://github.com/D-James-GH/cached_query/issues/100).

### Result typing
- Since 3.0.0, **sealed classes**: `sealed class QueryStatus<T>` with
  `QueryInitial`, `QueryLoading(isRefetching, isInitialFetch, retryCount, T? data)`,
  `QueryError(dynamic error, StackTrace, T? data)`, `QuerySuccess(T data)`.
  Convenience getters `isLoading`/`isSuccess`/`isError`/`isInitial`, nullable
  `data` on the base type, and `dynamic get error`
  (https://github.com/D-James-GH/cached_query/blob/main/packages/cached_query/lib/src/query_state.dart).
- The design was driven by #48 ("Implement states as sealed classes"); the
  maintainer's one requirement was that previous data stay available while
  loading ("otherwise it would remove some of the usefulness of the package")
  (https://github.com/D-James-GH/cached_query/issues/48).
- Mutation state is sealed too (3.0.0-dev.16 CHANGELOG).

### Mutations
- `Mutation<TData, TArg>(key?, mutationFn:, invalidateQueries: ['posts'], onStartMutation:, onSuccess:, onError:)`;
  `final created = await mutation.mutate(arg)`; keyed mutations are cached so
  their state can be observed elsewhere (README "Mutation").
- Optimistic updates: `onStartMutation` returns a fallback; `onError`
  receives it for rollback; updates go through `query.update((old) => ...)` or
  `CachedQuery.instance.updateQuery` (README "Optimistic updates").
- The mutation function parameter was renamed `queryFn` → `mutationFn` in 3.0
  after #81 ("unintuitive naming")
  (https://github.com/D-James-GH/cached_query/issues/81).

### Keys
- `Object key`, stringified: a `String` is used as-is, anything else is
  `jsonEncode`d (`encodeKey`)
  (https://github.com/D-James-GH/cached_query/blob/main/packages/cached_query/lib/src/util/encode_key.dart).
  So list/map keys work but must be JSON-encodable; there is no `QueryKey` type.
- Composite keys were asked for twice (#13 in 2023, #41 in 2024). The
  maintainer initially preferred a `filterFn` over key-prefix "hidden magic"
  (https://github.com/D-James-GH/cached_query/issues/13,
  https://github.com/D-James-GH/cached_query/issues/41). Prefix/inclusive
  invalidation was asked for in #68.

### TanStack feature claims
- Offered: `staleDuration` (renamed from `refetchDuration` in 3.0 after #82),
  `cacheDuration`, stale-while-revalidate via stream, dedup (shared instance),
  retry for queries and infinite queries (3.7.0), polling interval (3.3.0),
  `refetchOnResume` and `refetchOnConnection` (Flutter package; connectivity
  check pings example.com), infinite queries with previous-page fetch (3.4.0),
  `shouldFetch`/`enabled`, `setQueryData` that creates the query if absent
  (3.2.0), persistence through `StorageInterface` + `cached_storage` (sqflite),
  a DevTools extension, global observers/logging
  (CHANGELOG https://github.com/D-James-GH/cached_query/blob/main/packages/cached_query/CHANGELOG.md;
  READMEs).
- Not offered: `placeholderData`/`keepPreviousData`, `select`, cancellation
  (#84, withdrawn by the reporter after the maintainer rejected abort-on-unsubscribe and disliked adding a parameter to `queryFn`), refetch-on-window-focus as such (resume only),
  a query-key type, offline mutation queue (#69 open), cache scopes (#70 open).

### Testing
- Substantial pure-Dart suite: `query_test.dart` (29 KB),
  `infinite_query_test.dart` (35 KB), `mutation_test.dart`,
  `cached_query_test.dart`, `query_observer_test.dart`,
  `query_state_notifier_test.dart`, `connection_controller_test.dart`,
  `app_resume_test.dart`, `query_controller_test.dart` (uses `fake_async`);
  Flutter widget tests for `QueryBuilder`, `InfiniteQueryBuilder`,
  `QueryListener`, connectivity (GitHub contents API for
  `packages/cached_query/test` and `packages/cached_query_flutter/test`).
- Users still hit pending timers in widget tests; the answer is
  `CachedQuery.instance.dispose()` or `fake_async` (#94)
  (https://github.com/D-James-GH/cached_query/issues/94).

### Recurring complaints (issue tracker)
- **Naming/typing hygiene**: `refetchDuration` meant "stale" (#82),
  `queryFn` on a mutation (#81), pervasive `dynamic` internally (#51, a long
  exchange where the reporter argues "dynamic is both like a linter warning and
  a flash bang"), builder loses its type when `QueryConfig` is passed (#87)
  (https://github.com/D-James-GH/cached_query/issues/51).
- **State should carry actions and pagination facts**: #77 asks for
  `hasNextPage`/`fetchNextPage` on the state so a single object can be passed
  down, citing React Query; the maintainer explains the stream/bloc-like
  architecture cannot put methods on state, and adds `hasReachedMax` instead
  (https://github.com/D-James-GH/cached_query/issues/77).
- **Cache priming and composition**: cannot pre-load cache entries without a
  fake query (#74, led to `setQueryData` creating queries); combining/mapping
  queries or hand-rolled normalisation is hard (#67, open; maintainer: "A
  normalized cache will not be supported in this package")
  (https://github.com/D-James-GH/cached_query/issues/74,
  https://github.com/D-James-GH/cached_query/issues/67).
- **Lifecycle refetch surprises**: `refetchOnResume` refetched inactive
  queries in 3.x (#85, bug), refetch on resume while offline (#62), `shouldRefetch`
  ignored (#63), skip-initial-fetch-but-subscribe (#90).
- **Infinite query stuck state** ("CRITICAL BUG", #32) from a `_currentFuture`
  never reset (https://github.com/D-James-GH/cached_query/issues/32).
- **Integration asks**: Riverpod docs (#61 open; maintainer has "limited
  experience with riverpod"), dynamic key swapping while keeping one stream
  (#99), lifecycle documentation (#66 open), Windows/Linux storage (#26 open).

---

## 3. `flutter_query` (jezsung/query)

### Identity and status
- pub.dev: 0.11.1 on 2026-07-14; 59 versions since 0.0.1 (2020-09-30);
  160/160 points, 38 likes, 268 downloads/30d; deps `clock`, `collection`,
  `flutter`, `flutter_hooks`, `meta`
  (https://pub.dev/api/packages/flutter_query,
  https://pub.dev/packages/flutter_query/score). Companion
  `utopia_hooks_query` 0.7.0+2 (2026-09-08). The older `query_core` 0.2.1 is
  marked discontinued/unlisted on pub.dev (https://pub.dev/api/packages/query_core/score).
- GitHub `jezsung/query`: 32 stars, 2 forks, 3 open issues, last push
  2026-07-14, MIT. Docs at https://flutterquery.com.
- History matters here. In Feb 2025 the author answered "Is this project
  active or abandoned?" with: "this project is abandoned. I thought this pattern
  would be helpful but found my code to be unmanagable quickly. This approach
  leads to a very unflexible state management" (#3). In Dec 2025 he restarted,
  and rejected a large external PR (#4) in favour of his own TanStack-v5
  alignment, noting: "In the past, I had tried to make this project follow the
  Flutter style instead of aligning the APIs with the Tanstack Query which made
  the development harder and led to project abandonment"
  (https://github.com/jezsung/query/issues/3,
  https://github.com/jezsung/query/pull/4).

### Declaring and consuming a query
- Hooks only. `final result = useQuery(const ['greeting'], (context) => fetchGreeting());`
  inside a `HookWidget`, then `result.isLoading` / `result.isError` /
  `result.data!` (https://github.com/jezsung/query/blob/main/docs/content/docs/02-quick-start.mdx).
  The query function receives a context object (`QueryFunctionContext`, see
  `lib/src/core` listing).
- Hook set: `useQuery`, `useMutation`, `useInfiniteQuery`, `useQueryClient`,
  `useIsFetching`, `useIsMutating`, `useMutationState`
  (https://github.com/jezsung/query/blob/main/packages/flutter_query/README.md).
- `lib/src/widgets/` contains only `query_client_provider.dart` — no builder
  widgets. A GetX user asked for a non-hooks path (#70); the maintainer "may
  introduce a hook-independent API ... something that's widget-based"
  (https://github.com/jezsung/query/issues/70).

### Providing the client/cache
- `QueryClientProvider(client: QueryClient(), child: ...)` at the root; `useQueryClient()`
  in widgets (quick start). `QueryCache` is intentionally hidden from the
  public API "to keep it internal and not to introduce breaking changes too
  often" (#45 comment, https://github.com/jezsung/query/issues/45).

### Result typing
- Flat result with booleans plus a `status` enum (`QueryStatus.pending/success/error`)
  and nullable `data` (#72 shows `switch (result.status)`; quick start uses
  `isLoading`/`isError`/`data!`). Not sealed.

### Mutations
- `useMutation` with TanStack-style callbacks; `useMutationState`,
  `useIsMutating` exist (README hook list). `onSuccess`/`onError` on
  `useQuery` were requested (#72); the maintainer notes TanStack v5 removed them
  "since it turned out to be a footgun" and points to `useEffect`
  (https://github.com/jezsung/query/issues/72).

### Keys
- A `List`; compared with Dart deep `==`, so "keys can contain any Dart object
  that implements proper equality" — enums, class instances with `==`/`hashCode` —
  in contrast to TanStack's JSON-serialisation comparison
  (https://github.com/jezsung/query/blob/main/docs/content/docs/coming-from-tanstack-query.mdx).

### TanStack feature claims and deliberate divergences
- README claims: automatic caching with stale times, request deduplication,
  background refetching, stale-while-revalidate, optimistic updates with
  rollback, infinite queries, retries with exponential backoff, lifecycle-aware
  refetch on app resume (README "Why Flutter Query?").
- Documented divergences from TanStack (same doc):
  `staleTime`→`staleDuration` as a sealed `StaleDuration` (`StaleDuration(minutes: 5)`,
  `.infinity`, `.static`); `gcTime`→`GcDuration` (`.infinity`);
  `placeholderData`→`placeholder`; `initialData`→`seed`; `retry`+`retryDelay`
  collapsed into one `retry: (retryCount, error) => Duration?` (null stops).
  The doc argued against callback-form options because "Dart has no union type
  support", then 0.11.0 added sealed `Placeholder.value/.lazy/.keepPrevious`
  and `Seed.value/.lazy` anyway, as breaking changes
  (https://github.com/jezsung/query/blob/main/packages/flutter_query/CHANGELOG.md).
- Not offered: persistence ("not trivial ... take some time", #45), builder
  widgets, focus/online managers as public API, DevTools.
- `lib/src/core/abort_signal.dart` exists, i.e. cancellation plumbing is
  present in core.

### Testing
- By far the largest self-written suite among the ports: `use_query_test.dart`
  129 KB, `use_infinite_query_test.dart` 125 KB, `query_client_test.dart`
  113 KB, `infinite_query_observer_test.dart` 116 KB, `mutation_observer_test.dart`
  44 KB, `mutation_test.dart` 33 KB, `query_test.dart` 35 KB,
  `retry_controller_test.dart`, `query_key_test.dart`, etc.; CI and Codecov
  badges in the README (GitHub contents API for
  `packages/flutter_query/test/src/{hooks,core,widgets}`).
- Tests are written from the Dart side; nothing indicates that upstream
  TanStack test cases were ported.

### Recurring complaints (issue tracker)
- Abandonment/trust (#3). Same key on two screens crashed the app (#40, fixed
  0.7.0). `keepPreviousData` and disk persistence (#45). Hooks-only (#70).
  Query callbacks (#72). 0.11.1 fixed a runtime `type '(int, TError) => Duration?'
  is not a subtype ...` error when refetching an observer with a typed `TError`
  (CHANGELOG). Frequent pre-1.0 breaking renames.

---

## 4. `tanstack_query` (Phenek/flutter_tanstack_query)

### Identity and status
- pub.dev: 1.2.7 on 2026-04-15; 13 versions since 1.0.0 (2025-12-18);
  140/160 points, 7 likes, 42 downloads/30d; deps `flutter`, `async`,
  `flutter_hooks`, `meta`, `provider`
  (https://pub.dev/api/packages/tanstack_query,
  https://pub.dev/packages/tanstack_query/score).
- GitHub `Phenek/flutter_tanstack_query`: 3 stars, 0 forks, 0 open issues,
  last push 2026-05-19; GitHub detects no licence file
  (https://github.com/Phenek/flutter_tanstack_query).
- Provenance: the author ran this implementation in production, offered it as
  PR #4 to jezsung/query ("Upgrade to TanStack React Query v5 architecture"),
  was turned down, and published it separately (https://github.com/jezsung/query/pull/4,
  https://github.com/jezsung/query/issues/2).
- Self-description: "This librairy and documentation is a COPY CAT as it
  closely follows TanStack Query's API architecture and design, and
  intentionally mirrors every aspects of the JavaScript library"
  (https://github.com/Phenek/flutter_tanstack_query/blob/main/README.md).

### Declaring and consuming a query
- Hooks only, TanStack v5 names verbatim:
  `final todosQuery = useQuery<List<Map<String, dynamic>>>(queryKey: ['todos'], queryFn: getTodos);`
  then `todosQuery.isPending` / `isError` / `data ?? []` (README example).
  `useInfiniteQuery`, `useMutation`, `useQueryClient`.

### Providing the client/cache
- `QueryClient(defaultOptions: DefaultOptions(queries: QueryDefaultOptions(enabled:, staleTime: 0, refetchOnWindowFocus:, refetchOnReconnect:)), queryCache: QueryCache(config: QueryCacheConfig(onError:)), mutationCache: MutationCache(config: ...))`
  then `QueryClientProvider(client:, child:)` (README). An earlier design had a
  static `QueryClient.instance` (removed in 1.1.0, CHANGELOG).

### Result typing
- Flat booleans (`isPending`, `isError`, `isFetchingNextPage`, `hasNextPage`,
  ...) with nullable `data` (README; CHANGELOG 1.2.3).

### Mutations
- `useMutation(mutationFn:, onSuccess: (_) => queryClient.invalidateQueries(queryKey: ['todos']))`,
  `mutate`/`mutateAsync`/`resetMutation`, mutation `context` in callbacks
  (README; CHANGELOG 1.1.0, 1.2.2).

### Keys
- `List<Object>` (README). Comparison semantics are not documented.

### TanStack feature claims
- `staleTime`/`gcTime` as millisecond numbers, `retry`/`retryDelay` with
  exponential backoff and a `Retryer`, GC scheduling, `refetchOnMount`,
  `initialData`, `placeholderData`, `refetchOnWindowFocus`/`refetchOnReconnect`
  through exported `focusManager`/`onlineManager` **that the app must wire
  itself** with `AppLifecycleListener` and a connectivity package (README
  "Refetching on focus and reconnect"), infinite queries built as "port of
  `infiniteQueryBehavior.ts`" and "port of `InfiniteQueryObserver.ts`"
  (CHANGELOG 1.2.6).
- The README bullet list also claims "Prefetching, cancellation & React
  Suspense support", copied from TanStack; nothing in the changelog or tests
  substantiates cancellation or a Suspense analogue.

### Testing
- Eight test files: `use_query_test.dart` (37 KB), `use_infinite_query_test.dart`
  (50 KB), `use_mutation_test.dart`, `refetch_on_events_test.dart`,
  `managers_test.dart`, `mutation_observer_test.dart`, `provider_mount_test.dart`,
  `mapping_integration_test.dart` (GitHub contents API for
  `packages/tanstack_query/test`). Own tests, not upstream ports.

### Recurring complaints
- No user issues exist yet (0 open, 1 closed PR). The changelog itself records
  the class of bugs a from-memory port produces: GC evicting *active* queries
  after `invalidateQueries()`/`clear()` (1.2.6), `gcTime: 0` treated as "GC
  disabled" (1.2.7), infinite rebuilds with an inline `mutationKey` (1.2.5),
  stuck `isFetchingNextPage` (1.2.6), mismatched generic cache entries
  (`InfiniteQueryResult<Object>` vs `<int>`) discarded at runtime (1.2.6)
  (https://github.com/Phenek/flutter_tanstack_query/blob/main/packages/tanstack_query/CHANGELOG.md).

---

## 5. The long tail: other packages that claim to port TanStack/React Query

All found via pub.dev search on 2026-09-08. Each is single-author and most are
under a year old; together they show the same ideas being rebuilt repeatedly.

| Package | Latest (date) | Pts / likes / DL30d | Stars | Shape | Notable |
|---|---|---|---|---|---|
| `tanquery` (+`tanquery_flutter`, `tanquery_devtools`) | 0.8.0 (2026-05-23) | 160 / 6 / 38 | 5 | pure-Dart core + `DartQueryProvider`, `QueryBuilder(queryKey: QueryKey([...]), queryFn:, builder:(ctx,state))`, `MutationBuilder`, `InfiniteQueryBuilder`, `QueriesBuilder` | `QueryKey` value type; `fetchQuery`/`prefetchQuery`/`ensureQueryData`; provider forwards app lifecycle to a focus manager; devtools overlay; CI runs format/analyze/test (https://github.com/OttomanDeveloper/tanquery/blob/master/README.md) |
| `swrly` (+`swrly_hooks`) | 0.3.1 (2026-09-02) | 160 / 2 / 422 | 1 | `QueryBuilder(queryKey:, queryFn:, staleTime:, builder:(ctx,state,refetch))`; `Query`/`QueryFamily` *definition* objects; `QueryClient.instance` | Hooks split into a companion package because "Dart has no peer-dependency story"; `onMutate` returns a rollback closure; honest Riverpod comparison table ("`staleTime` ... hand-rolled" in Riverpod); claims 100% line coverage (https://github.com/redhotsixbull/swrly/blob/main/README.md) |
| `qora` (+`qora_flutter`, `qora_hooks`, overlay) | 1.2.0 (2026-06-15) | 160 / 2 / 38 | 6 | `QoraScope(client:)`, `QoraBuilder<T>(queryKey:, fetcher:, builder:(ctx, state, fetchStatus) => switch (state) { Loading(:final previousData) ..., Success(:final data) ..., Failure(...) })` | Two-axis sealed state (`QoraState` × `FetchStatus`) mirroring TanStack's `status`/`fetchStatus`; offline mutation queue; 14 open issues incl. "type-safe query keys (code-gen or builder pattern)" (#34) and `select` (#22); bugs #1 (unhandled async error leaked via `unawaited`), #12 (`Scope.of` in `initState` crashes in `AppBar`) (https://github.com/meragix/qora) |
| `flutter_query_client` | 4.1.0 (2026-09-08) | 140 / 2 / 39 | 0 | `QueryController` classes (`super(baseKey: 'posts')`) provided through `BlocProvider`; `QueryProvider`/`QueryBuilder<C,T>` | Built on bloc; `NetworkMode.online/always/offlineFirst` (https://github.com/ManiacOne/flutter_query_client) |
| `zenquery` | 1.0.2 (2026-03-16) | 150 / 5 / 41 | 9 | "opinionated wrapper around Riverpod ... inspired by TanStack Query" | The only one that builds *on* the incumbent instead of beside it (https://github.com/definev/zensuite) |
| `queryx` | 0.1.1 (2026-08-28) | 160 / 2 / 142 | 0 | engine "works with any state manager" | caching, dedup, retry, pagination, mutations, offline sync claimed (https://github.com/Noman-Baig/queryx) |
| `smart_query` | 1.0.0 (2026-03-28) | 160 / 6 / 12 | 0 | — | Its own 4 open issues are the roadmap: DevTools, offline mutation queue, true cancellation (`AbortSignal`/`CancelToken`), persistent storage (https://github.com/adityarajsingh0190/smart_query/issues) |
| `flutter_query_plus` | 0.0.6 (2026-03-10) | 160 / 1 / 30 | 1 | "React Query-inspired" | (https://github.com/febin52/flutter_query) |
| `flutter_tanstack_query` (Haraprosad) | 0.0.1+3 (2025-09-25) | 130 / 18 / 3 | 9 | "inspired by TanStack Query (React Query)", Hive persistence | Only issue: "Hive no longer maintained" (https://github.com/Haraprosad/flutter_tanstack_query/issues/1) |
| `getx_query` | 0.1.1 (2026-07-22) | 150 / 0 / 28 | — | Rx-backed `useQuery`/`useMutation` over `flutter_query` for GetX | Exists because `flutter_query` is hooks-only (cf. jezsung/query#70) |
| `fuery`/`fuery_core` | 0.0.1 / 0.2.2 (2024-04-26) | 150 / 2 / 19–27 | 3 | — | Dormant since 2024 |
| `dartquery` | 1.0.0 (2025-07-29) | 150 / 2 / 23 | — | "similar to React Query" | — |

Sources: `https://pub.dev/api/packages/<name>` and `/score` for each; GitHub
repository API for stars/issues.

---

## 6. Riverpod `FutureProvider` / `AsyncNotifier` — the incumbent

### Identity and status
- `riverpod` 3.4.3 (2026-09-03), 160/160, 4,028 likes, 3,019,128 downloads/30d,
  Flutter Favorite; `flutter_riverpod` 3.4.3, 140/160, 2,906 likes, 2,947,503
  downloads/30d (https://pub.dev/api/packages/riverpod,
  https://pub.dev/packages/riverpod/score, https://pub.dev/api/packages/flutter_riverpod).
- GitHub `rrousselGit/riverpod`: 7,378 stars, 1,109 forks, 154 open issues,
  pushed 2026-09-08 (https://github.com/rrousselGit/riverpod).
- Positioning in its own docs: "Providers are essentially 'memoized functions'
  ... The most common use-case for using providers is to perform a network
  request." (https://riverpod.dev/docs/concepts2/providers).

### Declaring and consuming a query
- Declaration is a **top-level final** (or `@riverpod` codegen):
  `final userProvider = FutureProvider<User>((ref) async { ... });` or a class
  `class TodosNotifier extends AsyncNotifier<List<Todo>> { FutureOr<List<Todo>> build() async { ... } }`
  with `AsyncNotifierProvider<TodosNotifier, List<Todo>>(TodosNotifier.new)`
  (https://riverpod.dev/docs/concepts2/providers, https://riverpod.dev/docs/whats_new).
- Consumption: `ref.watch(userProvider)` inside `ConsumerWidget`/`Consumer`
  (or `hooks_riverpod`), yielding `AsyncValue<User>`; parameterised via
  `.family`: `ref.watch(userProvider('123'))` (https://riverpod.dev/docs/concepts2/family).

### Providing the container
- `ProviderScope` at the root; `ProviderContainer` for pure Dart; overrides
  for tests; 3.0 adds `ProviderContainer.test`, `overrideWithBuild`,
  `WidgetTester.container` (https://riverpod.dev/docs/whats_new,
  https://riverpod.dev/docs/how_to/testing).

### Result typing
- `AsyncValue<T>` is a **sealed** class (`AsyncData`/`AsyncLoading`/`AsyncError`)
  whose subclasses can all carry a previous `value`; extension getters
  `isLoading`, `isRefreshing`, `isReloading`, `hasValue`, `hasError`,
  `requireValue`, `progress`, `retrying`, `isFromCache`; plus `when`/`map`.
  The recommended idiom is pattern matching with `hasValue: true`
  (https://pub.dev/documentation/riverpod/latest/riverpod/AsyncValue-class.html).
- The author's own open RFC #4172 says the abstraction "isn't quite perfect":
  UIs switch over state differently, values with extra metadata are hard to
  combine, and `AsyncData` vs `AsyncLoading` vs `AsyncError` "isn't quite
  matching user expectations"; he proposes splitting provider state from a
  separate sealed `Status` for UI matching
  (https://github.com/rrousselGit/riverpod/issues/4172). Related: #2894
  (`isLoading: true` on `AsyncData` should be `AsyncLoading`), #1570
  (`when(isRefreshing:)`, 41 comments).

### Mutations
- 3.0 introduces experimental `Mutation<T>()` declared as a top-level final,
  watched like a provider (`MutationIdle`/`MutationPending`/`MutationError`/`MutationSuccess`
  sealed states) and triggered with `addTodoMutation.run(ref, () async { await ref.read(todoListProvider.notifier).addTodo(...) })`.
  It exists to show side-effect progress and to stop providers being disposed
  mid-side-effect (https://riverpod.dev/docs/concepts2/mutations,
  https://riverpod.dev/docs/whats_new).
- Optimistic updates are manual: `final prev = state; try { state = optimistic; return await repo.post(); } catch (_) { state = prev; }`
  (author's answer in https://github.com/rrousselGit/riverpod/issues/3938).

### Keys
- There are no query keys; identity is the provider object plus `family`
  parameters, which "need to have a consistent `==`/`hashCode`" — a `[1, 2, 3]`
  literal is explicitly wrong, and `riverpod_lint`'s `provider_parameters`
  rule exists to catch it (https://riverpod.dev/docs/concepts2/family).
- Invalidation is by provider: `ref.invalidate(userProvider)` or
  `ref.invalidate(userProvider('123'))`, all-params or one
  (https://riverpod.dev/docs/concepts2/auto_dispose).

### TanStack features, mapped
- **Caching / dedup**: inherent (one state per provider/param).
- **staleTime / gcTime**: **not built in.** The docs say "Currently, Riverpod
  does not offer a built-in way to keep state alive for a specific amount of
  time" and show a `Timer` + `ref.keepAlive()` extension
  (https://riverpod.dev/docs/concepts2/auto_dispose). Issue #1664 "Implement
  cacheTime/staleTime" has been open since 2022-09 with the author's snippet as
  the workaround (https://github.com/rrousselGit/riverpod/issues/1664).
  `autoDispose` disposes one frame after the last listener leaves.
- **Retries**: built in since 3.0, exponential 200 ms → 6.4 s, configurable
  per scope/provider with `retry: (retryCount, error) => Duration?`
  (https://riverpod.dev/docs/concepts2/retry, whats_new).
- **Refetch on focus / reconnect**: not built in.
- **Infinite queries**: not built in (#394 "Is there a nice way to implement
  List pagination with just FutureProvider?").
- **Optimistic updates**: manual (above).
- **Persistence**: experimental `persist(...)` on Notifiers with a storage
  interface and `riverpod_sqflite` (https://riverpod.dev/docs/concepts2/offline).
- **Pull-to-refresh / SWR**: `ref.refresh(provider.future)` with previous
  data available on `AsyncLoading`; the how-to guide walks through spinner vs
  indicator handling (https://riverpod.dev/docs/how_to/pull_to_refresh).

### Recurring complaints (issue tracker, most-commented)
- Missing `staleTime`/`cacheTime` (#1664 open, 31 reactions).
- "Redundant `isLoading` gap when combining providers" — chained async providers
  flash `AsyncLoading` a frame after their dependency updates (#4009 RFC, 73
  comments) (https://github.com/rrousselGit/riverpod/issues/4009).
- `AsyncValue` ergonomics (#4172, #2894, #1570, #67 "merge AsyncValue
  together" open since 2020 with 80 comments).
- Keeping a list provider and an item provider for the same entity in sync
  (#3781 open, 46 comments) (https://github.com/rrousselGit/riverpod/issues/3781).
- Using `ref` after an async gap / `mounted` (#4096, #1879); `autoDispose`
  plus `ListView.builder` crashes (#2728).
- API churn: the unified-syntax RFCs #4008 (202 comments) and #4752 (144) —
  the API is still being redesigned in 2026.

---

## 7. Synthesis

### API idioms Flutter developers evidently like
1. **Builder widgets as the default, hooks as an opt-in.** fquery added
   `QueryBuilder`/`MutationBuilder` specifically so users need not extend
   `HookWidget` (CHANGELOG 1.2.0); flutter_query's hooks-only surface drew a
   request for a widget API and spawned `getx_query`; swrly split hooks into a
   companion package for the same reason; cached_query, tanquery and qora ship
   builders first. A hard `flutter_hooks` dependency is a repeated adoption
   blocker (jezsung/query#70; swrly README).
2. **Sealed result states that keep previous data.** cached_query moved to
   sealed `QueryStatus` on user request with the explicit constraint that data
   survives loading (#48); qora's `switch (state) { Loading(:final previousData) ... }`
   is its headline; Riverpod's `AsyncValue` is sealed and its author is
   redesigning it to match *more* precisely what UIs switch on (#4172). Flat
   `isLoading`/`data!` records (fquery, flutter_query, tanstack_query) are the
   TanStack literal translation and nobody praises them.
3. **List keys with real deep equality, ideally typed.** Every package that
   started with string keys or shallow equality got the same issue
   (fquery#44, cached_query#13/#41); flutter_query documents Dart-`==` keys as a
   feature; tanquery has a `QueryKey` value type; qora has an open issue for
   typed keys; swrly's `QueryFamily` builds keys by construction.
4. **`Duration`-typed options with named sentinel values**, not millisecond
   ints: flutter_query's `StaleDuration.infinity`/`.static`, `GcDuration.infinity`,
   and cached_query's rename `refetchDuration`→`staleDuration` after users
   misread it (#82).
5. **A pure-Dart core with a thin Flutter binding**, usable from repositories,
   blocs and tests: cached_query's strongest selling point, tanquery/qora/fquery_core
   copy it, and jezsung called the split "good practice" (PR #4).
6. **Plain `X.of(context)` access to the client** (fquery#46), and a client
   that is a "complete API on its own" for prefetch/imperative use (swrly,
   cached_query `query.result`, tanquery `fetchQuery`).
7. **Results that carry actions, not just state**: cached_query#77 asked for
   `fetchNextPage`/`hasNextPage` on what the builder receives so one object can
   be handed to a paging widget — exactly what TanStack's observer result does.

### Recurring pain points across trackers
1. **Flutter re-entrancy crashes** — "setState()/markNeedsBuild() called during
   build" or "when widget tree was locked" when the same query is observed on
   two routes or notified during dispose (fquery#6, #57 open; jezsung#40;
   qora#12). Notification timing relative to the frame is the number-one
   binding bug.
2. **Runtime type errors from generics** — `Query<T, dynamic>` vs `Query<T, Exception>`
   casts swallowed by a broad `catch` (fquery#47), pervasive `dynamic`
   (cached_query#51), builders losing their type (cached_query#87), retry
   closure subtype errors (flutter_query 0.11.1), mismatched infinite-query
   entries discarded (tanstack_query 1.2.6).
3. **Invalidation and refetch semantics** — invalidate not refetching
   (fquery#25/#50), refetch on resume hitting inactive queries (cached_query#85)
   or offline devices (#62), infinite queries getting stuck (cached_query#32,
   fquery#60/#61, tanstack_query 1.2.6), GC evicting active queries
   (tanstack_query 1.2.6). These are precisely the behaviours upstream's test
   suite pins down.
4. **Testing story** — pending timers fail widget tests (fquery#35,
   cached_query#94); no testing guide (fquery#48 open); only cached_query
   documents `fake_async`.
5. **Naming drift and churn** — renames of `refetchDuration`, `queryFn`,
   `initialData`→`seed`, `placeholderData`→`placeholder`, `QueryClient`→`QueryCache`,
   `QueryClientProvider`→`CacheProvider`; three incompatible fquery generations;
   flutter_query's abandonment and restart; Riverpod's ongoing syntax RFCs.
6. **Cache priming, composition and per-entity sync** — pre-loading entries
   (fquery#47, cached_query#74), combining or mapping queries (cached_query#67),
   list-vs-detail entity sync (riverpod#3781). Maintainers consistently decline
   normalised caches; users want at least `setQueryData` that creates entries,
   `select`, and `keepPreviousData` (flutter_query#45, qora#22).
7. **Ecosystem integration** — how to use a query cache with Riverpod/Bloc/GetX
   (cached_query#61 open, jezsung#70, swrly's five pattern examples); persistence
   requests everywhere (fquery#36, flutter_query#45, smart_query#2).
8. **Bus factor** — every dedicated package is one person; the two most
   feature-complete ones have each had a maintainer step away for a period.

### What none of them offer
- **Behavioural fidelity backed by upstream tests.** tanstack_query calls
  itself a "COPY CAT" and cites the `.ts` files it ports, but its tests are its
  own and its changelog lists GC/gcTime/infinite-query semantics bugs that
  upstream's suite would have caught. No package claims or documents a ported
  test suite, an upstream revision, or a list of deliberate divergences.
- **A sealed, data-retaining result that still exposes TanStack's full
  observer surface** (`fetchStatus`, `isPlaceholderData`, `isStale`,
  `failureCount`, `refetch`, `fetchNextPage`, ...). cached_query is sealed but
  state-only; qora has two axes but a small surface; the hooks ports have the
  surface but flat booleans.
- **Automatic focus/online wiring together with a typed core.** cached_query_flutter
  wires resume/connectivity; tanstack_query exports managers the app must feed;
  Riverpod has neither. Nobody offers `refetchOnWindowFocus`/`refetchOnReconnect`
  defaults plus a Dart-only core plus typed results in one package.
- **Typed query keys** (qora#34 open; swrly's `QueryFamily` is the closest).
- **Cancellation** reaching the query function (`AbortSignal` analogue): only
  flutter_query has plumbing; cached_query#84 and smart_query#3 are requests.
- **A first-class bridge to Riverpod.** zenquery wraps Riverpod; nobody bridges
  a TanStack-style cache *into* `ref.watch`, and cached_query's maintainer
  declined for lack of Riverpod experience (#61).
- **A documented testing recipe** for widget tests with fake time; the ports
  either lack tests or leave users to discover `fake_async`.

### Implications for the binding-shape ticket (for the map, not decisions)
- Ship builder widgets (`QueryBuilder`, `MutationBuilder`, infinite/queries
  variants) as the primary API; treat hooks as an optional companion package.
- Expose a sealed `QueryResult` that keeps `data` on loading/error *and*
  carries the observer actions and TanStack's `fetchStatus` axis; keep flat
  boolean getters as conveniences on the sealed base.
- Keep `QueryKey` as a value type with deep equality and consider a typed
  key/family helper; keep `StaleDuration`/`GcDuration`-style sealed options
  (already D9).
- Make notification-vs-frame timing a tested invariant of the binding
  (post-frame/scheduler-aware flush), since it is the dominant bug class.
- Provide `QueryClient.of(context)`, automatic lifecycle/connectivity wiring
  with opt-out, and a testing guide with fake time — the gaps users hit first.
