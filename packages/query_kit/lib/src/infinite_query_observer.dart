/// [InfiniteQueryObserver]: a [QueryObserver] that also pages.
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
/// Everything [QueryObserver] does applies — subscribe, [currentResult],
/// [refetch], [setOptions], [destroy] — with an [InfiniteData] as the
/// query's data (or whatever a `select` makes of it). On top, it adds:
///
/// - paging: [fetchNextPage] and [fetchPreviousPage];
/// - whether there is more: [hasNextPage] and [hasPreviousPage];
/// - which fetch is running or failed: [isFetchingNextPage],
///   [isFetchingPreviousPage], [isFetchNextPageError],
///   [isFetchPreviousPageError], and [isRefetching] / [isRefetchError]
///   narrowed to refetches of the pages already held.
///
/// These live on the observer rather than on the result, because the
/// sealed [QueryResult] is shared by every kind of query. A listener is
/// still told when one of them changes, whether or not the result did, so
/// reading them in the listener is always up to date. (TanStack Query puts
/// them on its infinite result object instead.)
///
/// ```dart
/// final observer = InfiniteQueryObserver(
///   client,
///   InfiniteQueryObserverOptions<List<Post>, int>(
///     queryKey: QueryKey(['feed']),
///     pageFn: (context) => api.feed(offset: context.pageParam),
///     initialPageParam: 0,
///     getNextPageParam: (page, pages, pageParam, pageParams) =>
///         page.isEmpty ? null : pageParam + page.length,
///   ),
/// );
/// final unsubscribe = observer.subscribe((result) {
///   if (result case QuerySuccess(:final data)) {
///     render(data.flatten<Post>(), canLoadMore: observer.hasNextPage);
///   }
/// });
/// // When the user scrolls to the end:
/// if (observer.hasNextPage && !observer.isFetchingNextPage) {
///   await observer.fetchNextPage();
/// }
/// ```
///
/// {@category Observers}
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
  /// Always the paging functions of the options in force, including after
  /// a [setOptions], so [hasNextPage] asks the same `getNextPageParam` the
  /// next fetch will use.
  InfiniteQueryOptions<TPageData, TPageParam> get infiniteOptions =>
      _pagingOptionsOf(options.behavior);

  /// Replaces the options, taking the infinite options a user writes — the
  /// typed form of [setOptions], which behaves the same otherwise: a new key
  /// moves the observer to another query, and a change that makes a fetch
  /// due starts one.
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

  /// Whether [fetchNextPage] would fetch anything: there are pages, and
  /// `getNextPageParam` returns a param for the last one. False before the
  /// first page has arrived.
  bool get hasNextPage =>
      hasNextPageOf<TPageData, TPageParam>(infiniteOptions, _data);

  /// Whether [fetchPreviousPage] would fetch anything: there are pages,
  /// `getPreviousPageParam` is set, and it returns a param for the first
  /// one. False before the first page has arrived.
  bool get hasPreviousPage =>
      hasPreviousPageOf<TPageData, TPageParam>(infiniteOptions, _data);

  FetchDirection? get _fetchDirection {
    final meta = currentQuery.state.fetchMeta;
    return meta is FetchMore ? meta.direction : null;
  }

  /// Whether a [fetchNextPage] is in flight — the "loading more" state at
  /// the end of a list. A refetch of the held pages does not count.
  bool get isFetchingNextPage =>
      currentResult.isFetching && _fetchDirection == FetchDirection.forward;

  /// Whether a [fetchPreviousPage] is in flight — the "loading more" state
  /// at the start of a list.
  bool get isFetchingPreviousPage =>
      currentResult.isFetching && _fetchDirection == FetchDirection.backward;

  /// Whether the query's error came from a [fetchNextPage] rather than a
  /// refetch or the initial load. The pages already held are still there;
  /// a UI typically shows a retry button at the end of the list.
  bool get isFetchNextPageError =>
      currentResult.isError && _fetchDirection == FetchDirection.forward;

  /// Whether the query's error came from a [fetchPreviousPage] rather than
  /// a refetch or the initial load.
  bool get isFetchPreviousPageError =>
      currentResult.isError && _fetchDirection == FetchDirection.backward;

  /// Whether the pages already held are being refetched — *not* a page being
  /// added. The result's own `isRefetching` is also true while a page is
  /// fetched, because the query is fetching and has data; this one leaves
  /// page fetches out.
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
  /// notification. The flags are not part of the result, so without this a
  /// `fetchPreviousPage` cancelling a `fetchNextPage` (same data, still
  /// fetching, other direction) and a `setOptions` whose new
  /// `getNextPageParam` says "no more" (same result, `hasNextPage` now false)
  /// would leave listeners — and a "load more" button — unaware.
  ///
  /// Exact, but lazy about user code: the six flags that follow from the
  /// result and the fetch direction are compared as values, while
  /// `hasNextPage`/`hasPreviousPage` — each a call into the user's paging
  /// function — are only re-asked when the paging functions or the data
  /// differ from what the last notification was answered over, old over old
  /// against new over new. Same functions over the same data is the same
  /// answer, so the paging functions are not called more often than needed.
  /// The data is part of
  /// the key because an equal *result* does not mean equal data: a `select`
  /// that collapses the change — `pages.length` over a page whose cursor
  /// turned null — would otherwise leave the flags flipping with no
  /// notification.
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
  /// query until [setInfiniteOptions] applies these options.
  QueryResult<TData> getOptimisticInfiniteResult(
    InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options,
  ) =>
      getOptimisticResult(client.infiniteObserverOptions(options));

  /// Fetches the page after the ones already held and appends it.
  ///
  /// The page's param is what `getNextPageParam` returns for the last held
  /// page. When that is `null` ([hasNextPage] is false), the page function
  /// is not called and the pages stay as they are. On a query with no pages
  /// yet, this loads the first page from `initialPageParam`.
  ///
  /// With [cancelRefetch] `true` (the default), a fetch already running on
  /// a query that holds pages — a refetch or another page fetch — is
  /// cancelled and this one starts; with `false`, or while the first page is
  /// still loading, this call joins the running fetch and adds no page. Check
  /// [isFetchingNextPage] first to avoid cancelling a page fetch of your
  /// own, as a scroll listener firing repeatedly would.
  ///
  /// With `maxPages` set, a page added past the limit drops the first page.
  /// Completes with [currentResult] once the fetch settled; it never
  /// completes with an error — a failed page fetch completes with a
  /// [QueryError], and [isFetchNextPageError] is then true.
  Future<QueryResult<TData>> fetchNextPage({bool cancelRefetch = true}) async {
    await executeFetch(
      cancelRefetch: cancelRefetch,
      meta: const FetchMore(FetchDirection.forward),
    );
    updateResult();
    return currentResult;
  }

  /// Fetches the page before the ones already held and prepends it.
  ///
  /// The mirror of [fetchNextPage]: the param comes from
  /// `getPreviousPageParam` for the first held page, and when there is none
  /// ([hasPreviousPage] is false, or `getPreviousPageParam` is not set) the
  /// pages stay as they are. [cancelRefetch] works as there, and with
  /// `maxPages` set a page added past the limit drops the last page. A
  /// failure completes with a [QueryError] and sets
  /// [isFetchPreviousPageError].
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
/// nothing outside the package needs it.
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
