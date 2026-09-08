/// Port of `query-core/src/infiniteQueryObserver.ts` at upstream `50680b98c`.
library;

import 'infinite_query.dart';
import 'query_client.dart';
import 'query_observer.dart';
import 'query_options.dart';
import 'query_result.dart';

/// Watches one infinite query, and pages it.
///
/// The paging surface lives here rather than on the result: upstream fattens
/// its result object with `hasNextPage` and friends because a React hook
/// returns exactly one value, while a sealed [QueryResult] cannot grow fields
/// per query kind without every consumer paying for them
/// (https://github.com/KoTTi97/flutter_query/issues/16).
class InfiniteQueryObserver<TPageData, TPageParam, TData>
    extends QueryObserver<InfiniteData<TPageData, TPageParam>, TData> {
  InfiniteQueryObserver(
    QueryClient client,
    InfiniteQueryObserverOptions<TPageData, TPageParam, TData> options,
  )   : _infiniteOptions = options,
        super(client, client.infiniteObserverOptions(options));

  InfiniteQueryObserverOptions<TPageData, TPageParam, TData> _infiniteOptions;

  /// The infinite-query options this observer was last given.
  InfiniteQueryObserverOptions<TPageData, TPageParam, TData>
      get infiniteOptions => _infiniteOptions;

  /// Replaces the options, keeping the paging half in step.
  void setInfiniteOptions(
    InfiniteQueryObserverOptions<TPageData, TPageParam, TData> options,
  ) {
    _infiniteOptions = options;
    setOptions(client.infiniteObserverOptions(options));
  }

  InfiniteData<TPageData, TPageParam>? get _data =>
      currentQuery.state.hasData ? currentQuery.state.data : null;

  /// Whether [fetchNextPage] would fetch anything.
  bool get hasNextPage =>
      hasNextPageOf<TPageData, TPageParam>(_infiniteOptions, _data);

  /// Whether [fetchPreviousPage] would fetch anything.
  bool get hasPreviousPage =>
      hasPreviousPageOf<TPageData, TPageParam>(_infiniteOptions, _data);

  FetchDirection? get _fetchDirection {
    final meta = currentQuery.state.fetchMeta;
    return meta is FetchMore ? meta.direction : null;
  }

  bool get isFetchingNextPage =>
      currentResult.isFetching && _fetchDirection == FetchDirection.forward;

  bool get isFetchingPreviousPage =>
      currentResult.isFetching && _fetchDirection == FetchDirection.backward;

  bool get isFetchNextPageError =>
      currentResult.isError && _fetchDirection == FetchDirection.forward;

  bool get isFetchPreviousPageError =>
      currentResult.isError && _fetchDirection == FetchDirection.backward;

  /// The result these options would produce right now — the infinite twin of
  /// [QueryObserver.getOptimisticResult], for a binding's first build.
  QueryResult<TData> getOptimisticInfiniteResult(
    InfiniteQueryObserverOptions<TPageData, TPageParam, TData> options,
  ) =>
      getOptimisticResult(client.infiniteObserverOptions(options));

  /// Fetches the page after the ones already held.
  Future<QueryResult<TData>> fetchNextPage({bool cancelRefetch = true}) async {
    await executeFetch(
      cancelRefetch: cancelRefetch,
      meta: const FetchMore(FetchDirection.forward),
    );
    updateResult();
    return currentResult;
  }

  /// Fetches the page before the ones already held.
  Future<QueryResult<TData>> fetchPreviousPage(
      {bool cancelRefetch = true}) async {
    await executeFetch(
      cancelRefetch: cancelRefetch,
      meta: const FetchMore(FetchDirection.backward),
    );
    updateResult();
    return currentResult;
  }
}

/// Same as [hasNextPage] on the observer, for callers holding only options and
/// data (a binding rendering from a cache snapshot, say).
bool hasNextPageOf<TPageData, TPageParam>(
  InfiniteQueryOptions<TPageData, TPageParam> options,
  InfiniteData<TPageData, TPageParam>? data,
) =>
    hasNextPage<TPageData, TPageParam>(options, data);

/// The backwards twin of [hasNextPageOf].
bool hasPreviousPageOf<TPageData, TPageParam>(
  InfiniteQueryOptions<TPageData, TPageParam> options,
  InfiniteData<TPageData, TPageParam>? data,
) =>
    hasPreviousPage<TPageData, TPageParam>(options, data);
