/// Infinite queries: pages, page params, and the fetch behaviour that turns
/// one fetch into a loop over them. Ports
/// `query-core/src/infiniteQueryBehavior.ts` at upstream `50680b98c`.
///
/// Shape decided on https://github.com/KoTTi97/flutter_query/issues/16: an
/// infinite query is an ordinary `Query<InfiniteData<TPageData, TPageParam>>`,
/// so everything the cache does — gc, invalidation, filters, persistence —
/// works on it unchanged. Only the *fetch* is different, and that difference
/// lives entirely in [InfiniteQueryBehavior].
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'cancel_token.dart';
import 'option_values.dart';
import 'query.dart';
import 'query_client.dart';
import 'query_key.dart';
import 'query_options.dart';

/// Every page fetched so far, and the param each was fetched with.
///
/// The two lists are the same length and in the same order: `pages[i]` was
/// fetched with `pageParams[i]`.
@immutable
final class InfiniteData<TPageData, TPageParam> {
  const InfiniteData({required this.pages, required this.pageParams});

  final List<TPageData> pages;
  final List<TPageParam> pageParams;

  bool get isEmpty => pages.isEmpty;

  /// Every item of every page, for the common case where a page is a list.
  Iterable<TItem> flatten<TItem>() =>
      pages.expand<TItem>((page) => page as Iterable<TItem>);

  InfiniteData<TPageData, TPageParam> copyWith({
    List<TPageData>? pages,
    List<TPageParam>? pageParams,
  }) =>
      InfiniteData<TPageData, TPageParam>(
        pages: pages ?? this.pages,
        pageParams: pageParams ?? this.pageParams,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InfiniteData<TPageData, TPageParam> &&
          _listEquals(other.pages, pages) &&
          _listEquals(other.pageParams, pageParams);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(pages),
        Object.hashAll(pageParams),
      );

  @override
  String toString() => 'InfiniteData(${pages.length} pages, $pageParams)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What a page function is handed.
///
/// Its own type rather than [QueryFunctionContext], so [pageParam] and
/// [direction] are typed instead of `Object?`.
class InfinitePageContext<TPageParam> {
  InfinitePageContext({
    required this.client,
    required this.queryKey,
    required this.pageParam,
    required this.direction,
    required QueryCancelToken Function() signalProvider,
    this.meta,
  }) : _signalProvider = signalProvider;

  final QueryClient client;
  final QueryKey queryKey;

  /// The param this page is being fetched with.
  final TPageParam pageParam;

  /// Which end of the pages this fetch is extending.
  final FetchDirection direction;

  final Object? meta;

  final QueryCancelToken Function() _signalProvider;

  /// Reading this marks the fetch as cancellable, exactly as it does for an
  /// ordinary query function — and not reading it leaves the fetch
  /// uncancellable, so a page that is already in flight still lands in the
  /// cache when the last observer goes away.
  QueryCancelToken get signal => _signalProvider();
}

/// Fetches one page.
typedef InfinitePageFn<TPageData, TPageParam> = FutureOr<TPageData> Function(
    InfinitePageContext<TPageParam> context);

/// Where the next (or previous) page starts, or `null` when there is none.
///
/// `null` is the end of the list — the reason a nullable [TPageParam] is a poor
/// choice of param type (https://github.com/KoTTi97/flutter_query/issues/16).
typedef PageParamFn<TPageData, TPageParam> = TPageParam? Function(
  TPageData page,
  List<TPageData> pages,
  TPageParam pageParam,
  List<TPageParam> pageParams,
);

/// Everything that describes an infinite query at the cache layer.
///
/// Extends [QueryOptions] over `InfiniteData`, because that is what the query
/// holds; the user's function is [pageFn] rather than `queryFn`, since it
/// returns one page.
@immutable
class InfiniteQueryOptions<TPageData, TPageParam>
    extends QueryOptions<InfiniteData<TPageData, TPageParam>> {
  const InfiniteQueryOptions({
    required QueryKey super.queryKey,
    required this.pageFn,
    required this.initialPageParam,
    required this.getNextPageParam,
    this.getPreviousPageParam,
    this.maxPages,
    this.pages,
    super.enabled,
    super.staleTime,
    super.gcTime,
    super.retry,
    super.retryDelay,
    super.networkMode,
    super.initialData,
    super.initialDataUpdatedAt,
    super.structuralSharing,
    super.meta,
  });

  final InfinitePageFn<TPageData, TPageParam> pageFn;

  /// The param the first page is fetched with.
  final TPageParam initialPageParam;

  final PageParamFn<TPageData, TPageParam> getNextPageParam;

  /// Only an option with one of these can page backwards.
  final PageParamFn<TPageData, TPageParam>? getPreviousPageParam;

  /// How many pages to keep. Older ones fall off the far end.
  final int? maxPages;

  /// How many pages to fetch up front — used to warm a cache with several
  /// pages, or to refetch a fixed number of them.
  final int? pages;
}

/// [InfiniteQueryOptions] plus the observer-only options.
@immutable
class InfiniteQueryObserverOptions<TPageData, TPageParam, TData>
    extends InfiniteQueryOptions<TPageData, TPageParam> {
  const InfiniteQueryObserverOptions({
    required super.queryKey,
    required super.pageFn,
    required super.initialPageParam,
    required super.getNextPageParam,
    super.getPreviousPageParam,
    super.maxPages,
    super.pages,
    super.enabled,
    super.staleTime,
    super.gcTime,
    super.retry,
    super.retryDelay,
    super.networkMode,
    super.initialData,
    super.initialDataUpdatedAt,
    super.structuralSharing,
    super.meta,
    this.select,
    this.placeholderData,
    this.refetchOnMount,
    this.refetchOnWindowFocus,
    this.refetchOnReconnect,
    this.refetchInterval,
    this.refetchIntervalInBackground,
    this.retryOnMount,
  });

  final TData Function(InfiniteData<TPageData, TPageParam> data)? select;
  final PlaceholderData<InfiniteData<TPageData, TPageParam>>? placeholderData;
  final RefetchOn? refetchOnMount;
  final RefetchOn? refetchOnWindowFocus;
  final RefetchOn? refetchOnReconnect;
  final RefetchInterval? refetchInterval;
  final bool? refetchIntervalInBackground;
  final bool? retryOnMount;
}

/// Which end of an infinite query a fetch is extending. Travels in
/// `FetchOptions.meta`, and so ends up in `QueryState.fetchMeta`.
@immutable
final class FetchMore {
  const FetchMore(this.direction);
  final FetchDirection direction;

  @override
  bool operator ==(Object other) =>
      other is FetchMore && other.direction == direction;

  @override
  int get hashCode => direction.hashCode;

  @override
  String toString() => 'FetchMore(${direction.name})';
}

/// Turns one fetch into a loop over pages.
///
/// Set by [QueryClient] when it defaults infinite-query options; users never
/// construct one.
@internal
class InfiniteQueryBehavior<TPageData, TPageParam>
    implements FetchBehavior<InfiniteData<TPageData, TPageParam>> {
  const InfiniteQueryBehavior(this.options, {this.pages});

  final InfiniteQueryOptions<TPageData, TPageParam> options;

  /// How many pages to fetch from the start; `null` refetches as many as the
  /// query already holds.
  final int? pages;

  @override
  void onFetch(
    FetchContext<InfiniteData<TPageData, TPageParam>> context,
    Query<InfiniteData<TPageData, TPageParam>> query,
  ) {
    final fetchMore = context.fetchOptions?.meta;
    final direction = fetchMore is FetchMore ? fetchMore.direction : null;
    final existing = context.state.hasData ? context.state.data : null;
    final oldPages = existing?.pages ?? const <Never>[];
    final oldPageParams = existing?.pageParams ?? const <Never>[];

    // Progress lives outside `fetchFn`, exactly as upstream keeps it in
    // `onFetch`: a retry continues from the page that failed instead of
    // starting the whole run again. Pages already fetched are not re-requested.
    var result = const InfiniteData<Never, Never>(
      pages: <Never>[],
      pageParams: <Never>[],
    ) as InfiniteData<TPageData, TPageParam>;
    var currentPage = 0;

    context.fetchFn = () async {
      var cancelled = false;

      // Read lazily: touching `context.signal` is what marks this fetch as
      // cancellable, and a page function that never asks for the token must
      // not have that decided for it. An uncancellable fetch whose last
      // observer goes away still finishes and fills the cache.
      QueryCancelToken? token;
      QueryCancelToken readSignal() =>
          token ??= (context.signal..onCancel(() => cancelled = true));

      Future<InfiniteData<TPageData, TPageParam>> fetchPage(
        InfiniteData<TPageData, TPageParam> data,
        TPageParam? param, {
        bool previous = false,
      }) async {
        if (cancelled) {
          throw const CancelledError();
        }
        if (param == null && data.pages.isNotEmpty) {
          return data;
        }

        final pageContext = InfinitePageContext<TPageParam>(
          client: context.client,
          queryKey: context.queryKey,
          pageParam: param as TPageParam,
          direction:
              previous ? FetchDirection.backward : FetchDirection.forward,
          meta: context.options.meta,
          signalProvider: readSignal,
        );

        final page = await options.pageFn(pageContext);
        final maxPages = options.maxPages;

        return InfiniteData<TPageData, TPageParam>(
          pages: previous
              ? addToStart<TPageData>(data.pages, page, maxPages)
              : addToEnd<TPageData>(data.pages, page, maxPages),
          pageParams: previous
              ? addToStart<TPageParam>(data.pageParams, param, maxPages)
              : addToEnd<TPageParam>(data.pageParams, param, maxPages),
        );
      }

      if (direction != null && oldPages.isNotEmpty) {
        final previous = direction == FetchDirection.backward;
        final oldData = InfiniteData<TPageData, TPageParam>(
          pages: List<TPageData>.of(oldPages),
          pageParams: List<TPageParam>.of(oldPageParams),
        );
        final param = previous
            ? previousPageParam<TPageData, TPageParam>(options, oldData)
            : nextPageParam<TPageData, TPageParam>(options, oldData);

        result = await fetchPage(oldData, param, previous: previous);
      } else {
        final remaining = pages ?? oldPages.length;
        do {
          final param = currentPage == 0
              ? (oldPageParams.isEmpty
                  ? options.initialPageParam
                  : oldPageParams.first)
              : nextPageParam<TPageData, TPageParam>(options, result);
          if (currentPage > 0 && param == null) {
            break;
          }
          result = await fetchPage(result, param);
          currentPage++;
        } while (currentPage < remaining);
      }

      return result;
    };
  }
}

/// Appends [item], dropping *one* item from the front when that would exceed
/// [max].
///
/// One item, not "down to [max]", because pages arrive one at a time — the same
/// arithmetic upstream does with `slice(1)`. A `null` or zero [max] keeps
/// everything, which is why `maxPages: 0` does not mean "keep no pages".
List<T> addToEnd<T>(List<T> items, T item, [int? max]) {
  final next = <T>[...items, item];
  return max != null && max > 0 && next.length > max ? next.sublist(1) : next;
}

/// Prepends [item], dropping one item from the back when that would exceed
/// [max].
List<T> addToStart<T>(List<T> items, T item, [int? max]) {
  final next = <T>[item, ...items];
  return max != null && max > 0 && next.length > max
      ? next.sublist(0, next.length - 1)
      : next;
}

/// The param the next page would be fetched with, or `null` if there is none.
TPageParam? nextPageParam<TPageData, TPageParam>(
  InfiniteQueryOptions<TPageData, TPageParam> options,
  InfiniteData<TPageData, TPageParam> data,
) {
  if (data.pages.isEmpty) {
    return null;
  }
  final last = data.pages.length - 1;
  return options.getNextPageParam(
    data.pages[last],
    data.pages,
    data.pageParams[last],
    data.pageParams,
  );
}

/// The param the previous page would be fetched with, or `null`.
TPageParam? previousPageParam<TPageData, TPageParam>(
  InfiniteQueryOptions<TPageData, TPageParam> options,
  InfiniteData<TPageData, TPageParam> data,
) {
  final getPreviousPageParam = options.getPreviousPageParam;
  if (getPreviousPageParam == null || data.pages.isEmpty) {
    return null;
  }
  return getPreviousPageParam(
    data.pages.first,
    data.pages,
    data.pageParams.first,
    data.pageParams,
  );
}

/// Whether [data] has a page after the ones it holds.
bool hasNextPage<TPageData, TPageParam>(
  InfiniteQueryOptions<TPageData, TPageParam> options,
  InfiniteData<TPageData, TPageParam>? data,
) =>
    data != null && nextPageParam<TPageData, TPageParam>(options, data) != null;

/// Whether [data] has a page before the ones it holds.
bool hasPreviousPage<TPageData, TPageParam>(
  InfiniteQueryOptions<TPageData, TPageParam> options,
  InfiniteData<TPageData, TPageParam>? data,
) =>
    data != null &&
    previousPageParam<TPageData, TPageParam>(options, data) != null;
