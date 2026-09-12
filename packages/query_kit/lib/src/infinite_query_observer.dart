/// Port of `query-core/src/infiniteQueryObserver.ts` at upstream `50680b98c`.
library;

import 'infinite_query.dart';
import 'query.dart';
import 'query_client.dart';
import 'query_observer.dart';
import 'query_options.dart';
import 'query_result.dart';

/// The paging flags that follow from the result and the fetch direction, as
/// one value, so a change in any of them can be told apart from none.
typedef _DirectionFlags = ({
  bool isFetchingNextPage,
  bool isFetchingPreviousPage,
  bool isFetchNextPageError,
  bool isFetchPreviousPageError,
  bool isRefetching,
  bool isRefetchError,
});

/// Watches one infinite query, and pages it.
///
/// The paging surface lives here rather than on the result: upstream fattens
/// its result object with `hasNextPage` and friends because a React hook
/// returns exactly one value, while a sealed [QueryResult] cannot grow fields
/// per query kind without every consumer paying for them
/// (https://github.com/KoTTi97/flutter_query/issues/16). What the shape
/// costs is paid in [shouldNotify]: a listener is told when a paging flag
/// changes, whether or not the result did.
class InfiniteQueryObserver<TPageData, TPageParam, TData>
    extends QueryObserver<InfiniteData<TPageData, TPageParam>, TData> {
  /// Creates an observer for [options], whose paging half becomes the query's
  /// fetch behaviour; otherwise exactly [QueryObserver.new].
  InfiniteQueryObserver(
    QueryClient client,
    InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options,
  ) : super(client, client.infiniteObserverOptions(options));

  /// The paging half of the current options.
  ///
  /// Read off the options' behaviour rather than held beside them: a copy
  /// kept in parallel went stale on a direct [setOptions], and `hasNextPage`
  /// then asked the old `getNextPageParam` while the fetch used the new one
  /// (fourth review, 2026-09-09).
  InfiniteQueryOptions<TPageData, TPageParam> get infiniteOptions =>
      _pagingOptionsOf(options.behavior);

  /// Replaces the options — the typed convenience over [setOptions].
  void setInfiniteOptions(
    InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options,
  ) =>
      setOptions(client.infiniteObserverOptions(options));

  /// Accepts any options that carry the paging behaviour — what
  /// [setInfiniteOptions], `QueryClient.infiniteObserverOptions` and an
  /// [InfiniteQueryOptions]'s own `behavior` produce. Plain observer options
  /// have no paging half; they would strip the behaviour from the shared
  /// query, whose next refetch would fail with `MissingQueryFunctionError`,
  /// so they are refused with an [UnsupportedError].
  @override
  void setOptions(
    QueryObserverOptionsBase<InfiniteData<TPageData, TPageParam>, TData>
        options,
  ) {
    _pagingOptionsOf(options.behavior);
    super.setOptions(options);
  }

  /// See [setOptions]; [getOptimisticInfiniteResult] is the typed form.
  @override
  QueryResult<TData> getOptimisticResult(
    QueryObserverOptionsBase<InfiniteData<TPageData, TPageParam>, TData>
        options,
  ) {
    _pagingOptionsOf(options.behavior);
    return super.getOptimisticResult(options);
  }

  static InfiniteQueryOptions<TPageData, TPageParam>
      _pagingOptionsOf<TPageData, TPageParam>(
    FetchBehavior<InfiniteData<TPageData, TPageParam>>? behavior,
  ) {
    if (behavior is InfiniteQueryBehavior<TPageData, TPageParam>) {
      return behavior.options;
    }
    throw UnsupportedError(
      'An InfiniteQueryObserver takes options with a paging behaviour — '
      'InfiniteQueryObserverOptions or InfiniteQuerySelectOptions via '
      'setInfiniteOptions / '
      'getOptimisticInfiniteResult, or what QueryClient.infiniteObserverOptions '
      'produces; plain observer options have no paging half.',
    );
  }

  InfiniteData<TPageData, TPageParam>? get _data =>
      currentQuery.state.hasData ? currentQuery.state.data : null;

  /// Whether [fetchNextPage] would fetch anything.
  bool get hasNextPage =>
      hasNextPageOf<TPageData, TPageParam>(infiniteOptions, _data);

  /// Whether [fetchPreviousPage] would fetch anything.
  bool get hasPreviousPage =>
      hasPreviousPageOf<TPageData, TPageParam>(infiniteOptions, _data);

  FetchDirection? get _fetchDirection {
    final meta = currentQuery.state.fetchMeta;
    return meta is FetchMore ? meta.direction : null;
  }

  /// Whether a [fetchNextPage] is in flight. Upstream's `isFetchingNextPage`.
  bool get isFetchingNextPage =>
      currentResult.isFetching && _fetchDirection == FetchDirection.forward;

  /// Whether a [fetchPreviousPage] is in flight. Upstream's
  /// `isFetchingPreviousPage`.
  bool get isFetchingPreviousPage =>
      currentResult.isFetching && _fetchDirection == FetchDirection.backward;

  /// Whether the query's error came from a [fetchNextPage] rather than a
  /// refetch or the initial load. Upstream's `isFetchNextPageError`.
  bool get isFetchNextPageError =>
      currentResult.isError && _fetchDirection == FetchDirection.forward;

  /// Whether the query's error came from a [fetchPreviousPage]. Upstream's
  /// `isFetchPreviousPageError`.
  bool get isFetchPreviousPageError =>
      currentResult.isError && _fetchDirection == FetchDirection.backward;

  /// Whether the pages already held are being refetched — *not* a page being
  /// added. The sealed result's `isRefetching` is true while a page is
  /// fetched, because the query is fetching and has data; upstream's infinite
  /// result subtracts the page directions, and so does this, where the other
  /// paging flags live.
  bool get isRefetching =>
      currentResult.isRefetching &&
      !isFetchingNextPage &&
      !isFetchingPreviousPage;

  /// The error twin of [isRefetching]: a refetch failed, not a page fetch.
  bool get isRefetchError => switch (currentResult) {
        QueryError<TData>(:final isRefetchError) =>
          isRefetchError && !isFetchNextPageError && !isFetchPreviousPageError,
        _ => false,
      };

  _DirectionFlags get _directionFlags => (
        isFetchingNextPage: isFetchingNextPage,
        isFetchingPreviousPage: isFetchingPreviousPage,
        isFetchNextPageError: isFetchNextPageError,
        isFetchPreviousPageError: isFetchPreviousPageError,
        isRefetching: isRefetching,
        isRefetchError: isRefetchError,
      );

  // What the last notification carried: the direction flags, and the paging
  // options and the data `hasNextPage`/`hasPreviousPage` were answered over.
  _DirectionFlags? _notifiedDirectionFlags;
  InfiniteQueryOptions<TPageData, TPageParam>? _notifiedPagingOptions;
  InfiniteData<TPageData, TPageParam>? _notifiedData;

  /// The base rule, or a change in any paging flag since the last
  /// notification. The flags are not part of the result, so a
  /// `fetchPreviousPage` cancelling a `fetchNextPage` (same data, still
  /// fetching, other direction) and a `setOptions` whose new
  /// `getNextPageParam` says "no more" (same result, `hasNextPage` now false)
  /// both left listeners — and a binding's "load more" button — unaware
  /// (fifth review, 2026-09-09). Upstream's flags ride on its result object
  /// and are compared with the rest of it.
  ///
  /// Exact, but lazy about user code: the six flags that follow from the
  /// result and the fetch direction are compared as values, while
  /// `hasNextPage`/`hasPreviousPage` — each a call into the user's paging
  /// function — are only re-asked when the paging functions or the data
  /// differ from what the last notification was answered over, old over old
  /// against new over new. Same functions over the same data is the same
  /// answer, and the ported suite counts those calls. The data is part of
  /// the key because an equal *result* does not mean equal data: a `select`
  /// that collapses the change — `pages.length` over a page whose cursor
  /// turned null — left the flags flipping with no notification when the
  /// write kept `dataUpdatedAt` too (ninth review, 2026-09-10, C13).
  ///
  /// The snapshot is taken here, on `true`, because `updateResult` notifies
  /// exactly then.
  @override
  bool shouldNotify(QueryResult<TData>? previous, QueryResult<TData> next) {
    final directionFlags = _directionFlags;
    final pagingOptions = infiniteOptions;
    final data = _data;
    final notify = super.shouldNotify(previous, next) ||
        directionFlags != _notifiedDirectionFlags ||
        _pageAvailabilityChanged(pagingOptions, data);
    if (notify) {
      _notifiedDirectionFlags = directionFlags;
      _notifiedPagingOptions = pagingOptions;
      _notifiedData = data;
    }
    return notify;
  }

  bool _pageAvailabilityChanged(
    InfiniteQueryOptions<TPageData, TPageParam> pagingOptions,
    InfiniteData<TPageData, TPageParam>? data,
  ) {
    final notified = _notifiedPagingOptions;
    if (notified == null ||
        (notified.getNextPageParam == pagingOptions.getNextPageParam &&
            notified.getPreviousPageParam ==
                pagingOptions.getPreviousPageParam &&
            identical(data, _notifiedData))) {
      return false;
    }
    final notifiedData = _notifiedData;
    return hasNextPageOf(pagingOptions, data) !=
            hasNextPageOf(notified, notifiedData) ||
        hasPreviousPageOf(pagingOptions, data) !=
            hasPreviousPageOf(notified, notifiedData);
  }

  /// The result these options would produce right now — the infinite twin of
  /// [QueryObserver.getOptimisticResult], for a binding's first build.
  ///
  /// This does not commit the query or its options. [hasNextPage],
  /// [hasPreviousPage] and paging actions continue to describe the committed
  /// query until [setInfiniteOptions] applies the previewed options.
  QueryResult<TData> getOptimisticInfiniteResult(
    InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options,
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

/// The top-level `hasNextPage` under a name the observer can reach from
/// inside its class, where `hasNextPage` is its own getter. Not exported:
/// nothing outside the package needs it (ninth review, 2026-09-10, C24).
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
