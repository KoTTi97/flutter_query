/// A Dart port of TanStack Query's `query-core`.
///
/// An independent community port: not affiliated with or endorsed by TanStack.
/// Ported against upstream `50680b98c`.
///
/// What is exported is the public surface, close to upstream's `index.ts`.
/// The plumbing between the pieces — the cache-side interfaces (`*Ref`), the
/// fetch context and behaviour, the retryer, the state actions — is not, so
/// that it can change without a major version.
library;

export 'src/cancel_token.dart';
export 'src/filters.dart';
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
export 'src/mutation.dart'
    hide
        MutationAction,
        MutationCacheRef,
        MutationContinueAction,
        MutationErrorAction,
        MutationFailedAction,
        MutationObserverRef,
        MutationPauseAction,
        MutationPendingAction,
        MutationSuccessAction;
export 'src/mutation_cache.dart';
export 'src/mutation_observer.dart';
export 'src/mutation_options.dart';
export 'src/mutation_result.dart';
export 'src/notify_manager.dart';
export 'src/online_manager.dart';
export 'src/option_values.dart';
export 'src/query.dart'
    hide
        FetchBehavior,
        FetchContext,
        QueryAction,
        QueryCacheRef,
        QueryContinueAction,
        QueryErrorAction,
        QueryFailedAction,
        QueryFetchAction,
        QueryInvalidateAction,
        QueryObserverRef,
        QueryPauseAction,
        QuerySetStateAction,
        QuerySuccessAction;
export 'src/query_cache.dart';
export 'src/query_client.dart';
export 'src/query_key.dart';
export 'src/query_observer.dart';
export 'src/query_options.dart';
export 'src/query_result.dart';
export 'src/query_state.dart';
export 'src/retryer.dart' show canFetch;
export 'src/structural_sharing.dart';
