/// A Dart port of TanStack Query's `query-core`.
///
/// An independent community port: not affiliated with or endorsed by TanStack.
/// Ported against upstream `50680b98c`.
///
/// What is exported is the public surface, close to upstream's `index.ts`.
/// The plumbing between the pieces — the cache-side interfaces (`*CacheRef`),
/// the retryer — is not, so that it can change without a major version. What
/// a public signature names *is* exported, so that every field can be typed
/// by its reader: the `QueryAction` and `MutationAction` families, the
/// `*ObserverRef` interfaces, and `FetchBehavior`/`FetchContext`, the type
/// of `QueryOptions.behavior` (ninth review, 2026-09-10, C23). They are
/// read-only from outside; dispatching an action, implementing a ref or
/// building a fetch context is not public API (fourth review, 2026-09-09),
/// and the refs' members are `@internal`.
library;

export 'src/cancel_token.dart';
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
export 'src/query_options.dart';
export 'src/query_result.dart';
export 'src/query_state.dart';
export 'src/retryer.dart' show canFetch;
export 'src/structural_sharing.dart';
