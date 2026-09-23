/// Asynchronous state management for Dart: fetching, caching, refetching,
/// invalidation and mutations of server data — a port of TanStack Query's
/// `query-core` that runs anywhere Dart runs, no Flutter needed.
///
/// > query_kit is an entirely AI-coded project: all code, tests and
/// > documentation were written by AI coding agents (Anthropic's Claude). A
/// > human maintainer set the goals and reviews releases, but did not write
/// > the code.
///
/// query_kit is an independent community port and is not affiliated with or
/// endorsed by TanStack. For Flutter widgets on top of it, see the
/// `query_kit_flutter` package.
///
/// ## Quick start
///
/// A [QueryClient] owns the cache. Describe a query with [QueryOptions] — a
/// [QueryKey] that identifies it and a query function that fetches it —
/// then fetch it imperatively with [QueryClient.query], or follow it with a
/// [QueryObserver], which fetches on subscribe, refetches when the data is
/// stale and something happens (focus, reconnect, invalidation), and reports
/// every change as a sealed [QueryResult].
///
/// ```dart
/// import 'package:query_kit/query_kit.dart';
///
/// Future<void> main() async {
///   final client = QueryClient()..mount();
///   final todosKey = QueryKey(['todos']);
///
///   // Fetch once and cache.
///   final todos = await client.query(QueryOptions<List<String>>(
///     queryKey: todosKey,
///     queryFn: (context) => fetchTodos(),
///     staleTime: const StaleTime.duration(Duration(seconds: 30)),
///   ));
///   print(todos);
///
///   // Observe: every change to the entry, as a sealed result.
///   final observer = QueryObserver(
///     client,
///     QueryObserverOptions<List<String>>(
///       queryKey: todosKey,
///       queryFn: (context) => fetchTodos(),
///     ),
///   );
///   final unsubscribe = observer.subscribe((result) {
///     switch (result) {
///       case QueryPending():
///         print('loading');
///       case QuerySuccess(:final data):
///         print('todos: $data');
///       case QueryError(:final error):
///         print('failed: $error');
///     }
///   });
///
///   // Mark stale and refetch what is observed.
///   await client.invalidateQueries(filters: QueryFilters(queryKey: todosKey));
///
///   unsubscribe();
///   client.unmount();
///   client.clear();
/// }
///
/// Future<List<String>> fetchTodos() async => ['Buy milk', 'Walk the dog'];
/// ```
///
/// ## Where to go next
///
/// The API is grouped into categories:
///
/// * **Client** — [QueryClient] and its defaults.
/// * **Queries**, **Options**, **Option values** — [QueryKey], [QueryOptions]
///   and the sealed option values such as [StaleTime], [RetryPolicy] and
///   [RefetchInterval].
/// * **Results** and **Combining results** — [QueryResult] and
///   [CombinedResult].
/// * **Observers** — [QueryObserver], [InfiniteQueryObserver],
///   [MutationObserver], [QueriesObserver], [MutationStateObserver].
/// * **Mutations** and **Infinite queries** — [MutationOptions],
///   [InfiniteQueryOptions] and friends.
/// * **Caches**, **Filters**, **Structural sharing**, **Errors**, **Managers**
///   — [QueryCache], [MutationCache], [QueryFilters], [replaceEqualDeep],
///   [AppFocusManager], [OnlineManager], [NotifyManager].
/// * **Advanced** — the plumbing: cache events, actions, fetch behaviours.
///
/// Guides, recipes and live examples are on the documentation site:
/// https://kotti97.github.io/query_kit/
library;

// Export policy (maintainer note): what is exported is the public surface,
// close to TanStack's `index.ts`. The plumbing between the pieces — the
// cache-side interfaces (`*CacheRef`), the retryer — is not, so that it can
// change without a major version. What a public signature names *is*
// exported, so that every field can be typed by its reader: the
// `QueryAction` and `MutationAction` families, the `*ObserverRef`
// interfaces, and `FetchBehavior`/`FetchContext`, the type of
// `QueryOptions.behavior`. They are read-only from outside; dispatching an
// action, implementing a ref or building a fetch context is not public API,
// and the refs' members are `@internal`.

export 'src/cancel_token.dart';
export 'src/combined_result.dart';
export 'src/filters.dart' hide describeFilters;
export 'src/focus_manager.dart';
export 'src/infinite_query.dart'
    hide
        InfiniteQueryBehavior,
        addToEnd,
        addToStart,
        hasNextPage,
        hasPreviousPage,
        nextPageParam,
        previousPageParam;
export 'src/infinite_query_observer.dart' hide hasNextPageOf, hasPreviousPageOf;
export 'src/mutation.dart' hide MutationCacheRef;
export 'src/mutation_cache.dart';
export 'src/mutation_observer.dart';
export 'src/mutation_options.dart';
export 'src/mutation_result.dart';
export 'src/mutation_state_observer.dart';
export 'src/notify_manager.dart';
export 'src/online_manager.dart';
export 'src/option_values.dart';
export 'src/queries_observer.dart';
export 'src/query.dart' hide QueryCacheRef;
export 'src/query_cache.dart';
export 'src/query_client.dart';
export 'src/query_key.dart';
export 'src/query_observer.dart';
export 'src/query_options.dart' hide isNoStructuralSharing;
export 'src/query_result.dart';
export 'src/query_state.dart';
export 'src/structural_sharing.dart' hide sharingBucketOf;
