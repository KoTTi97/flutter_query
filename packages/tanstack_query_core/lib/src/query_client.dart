/// Port of `query-core/src/queryClient.ts` at upstream `50680b98c`.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'filters.dart';
import 'focus_manager.dart';
import 'mutation.dart';
import 'mutation_cache.dart';
import 'mutation_options.dart';
import 'notify_manager.dart';
import 'online_manager.dart';
import 'option_values.dart';
import 'query.dart';
import 'query_cache.dart';
import 'query_key.dart';
import 'query_observer.dart';
import 'query_options.dart';
import 'query_state.dart';

/// Type-agnostic query defaults.
///
/// Upstream types its defaults `QueryObserverOptions<unknown, …>`; Dart cannot
/// express "options for any data type", so defaults carry exactly the options
/// that do not mention the data type. Anything that does (`queryFn`,
/// `initialData`, `select`, `placeholderData`) belongs to a single query and is
/// passed at the call site.
@immutable
class QueryDefaults {
  const QueryDefaults({
    this.enabled,
    this.staleTime,
    this.gcTime,
    this.retry,
    this.retryDelay,
    this.retryOnMount,
    this.networkMode,
    this.refetchOnMount,
    this.refetchOnWindowFocus,
    this.refetchOnReconnect,
    this.refetchInterval,
    this.refetchIntervalInBackground,
    this.meta,
  });

  final Enabled? enabled;
  final StaleTime? staleTime;
  final GcTime? gcTime;
  final RetryPolicy? retry;
  final RetryDelay? retryDelay;
  final bool? retryOnMount;
  final NetworkMode? networkMode;
  final RefetchOn? refetchOnMount;
  final RefetchOn? refetchOnWindowFocus;
  final RefetchOn? refetchOnReconnect;
  final RefetchInterval? refetchInterval;
  final bool? refetchIntervalInBackground;
  final Object? meta;

  QueryDefaults mergedWith(QueryDefaults? other) {
    if (other == null) return this;
    return QueryDefaults(
      enabled: other.enabled ?? enabled,
      staleTime: other.staleTime ?? staleTime,
      gcTime: other.gcTime ?? gcTime,
      retry: other.retry ?? retry,
      retryDelay: other.retryDelay ?? retryDelay,
      retryOnMount: other.retryOnMount ?? retryOnMount,
      networkMode: other.networkMode ?? networkMode,
      refetchOnMount: other.refetchOnMount ?? refetchOnMount,
      refetchOnWindowFocus: other.refetchOnWindowFocus ?? refetchOnWindowFocus,
      refetchOnReconnect: other.refetchOnReconnect ?? refetchOnReconnect,
      refetchInterval: other.refetchInterval ?? refetchInterval,
      refetchIntervalInBackground:
          other.refetchIntervalInBackground ?? refetchIntervalInBackground,
      meta: other.meta ?? meta,
    );
  }
}

/// Type-agnostic mutation defaults.
@immutable
class MutationDefaults {
  const MutationDefaults({
    this.retry,
    this.retryDelay,
    this.networkMode,
    this.gcTime,
    this.scope,
    this.meta,
  });

  final RetryPolicy? retry;
  final RetryDelay? retryDelay;
  final NetworkMode? networkMode;
  final GcTime? gcTime;
  final MutationScope? scope;
  final Object? meta;

  MutationDefaults mergedWith(MutationDefaults? other) {
    if (other == null) return this;
    return MutationDefaults(
      retry: other.retry ?? retry,
      retryDelay: other.retryDelay ?? retryDelay,
      networkMode: other.networkMode ?? networkMode,
      gcTime: other.gcTime ?? gcTime,
      scope: other.scope ?? scope,
      meta: other.meta ?? meta,
    );
  }
}

/// Client-wide defaults.
@immutable
class DefaultOptions {
  const DefaultOptions({this.queries, this.mutations});
  final QueryDefaults? queries;
  final MutationDefaults? mutations;
}

/// The cache's front door: everything imperative happens here.
class QueryClient {
  QueryClient({
    QueryCache? queryCache,
    MutationCache? mutationCache,
    DefaultOptions? defaultOptions,
    AppFocusManager? focusManager,
    OnlineManager? onlineManager,
    NotifyManager? notifyManager,
  })  : queryCache = queryCache ?? QueryCache(),
        mutationCache = mutationCache ?? MutationCache(),
        focusManager = focusManager ?? AppFocusManager(),
        onlineManager = onlineManager ?? OnlineManager(),
        notifyManager = notifyManager ?? NotifyManager.shared,
        _defaultOptions = defaultOptions ?? const DefaultOptions();

  final QueryCache queryCache;
  final MutationCache mutationCache;

  /// Owned by the client rather than global, so tests are hermetic
  /// (https://github.com/KoTTi97/flutter_query/issues/19).
  final AppFocusManager focusManager;
  final OnlineManager onlineManager;
  final NotifyManager notifyManager;

  DefaultOptions _defaultOptions;
  final Map<QueryKey, QueryDefaults> _queryDefaults =
      <QueryKey, QueryDefaults>{};
  final Map<QueryKey, MutationDefaults> _mutationDefaults =
      <QueryKey, MutationDefaults>{};

  int _mountCount = 0;
  void Function()? _unsubscribeFocus;
  void Function()? _unsubscribeOnline;

  /// Starts listening for focus and connectivity changes.
  void mount() {
    _mountCount++;
    if (_mountCount != 1) {
      return;
    }

    _unsubscribeFocus = focusManager.subscribe((focused) {
      if (focused) {
        mutationCache.resumePaused().ignore();
        queryCache.onFocus();
      }
    });

    _unsubscribeOnline = onlineManager.subscribe((online) {
      if (online) {
        mutationCache.resumePaused().ignore();
        queryCache.onOnline();
      }
    });
  }

  /// Stops listening. Balanced with [mount].
  void unmount() {
    _mountCount--;
    if (_mountCount != 0) {
      return;
    }
    _unsubscribeFocus?.call();
    _unsubscribeFocus = null;
    _unsubscribeOnline?.call();
    _unsubscribeOnline = null;
  }

  // ------------------------------------------------------------- reading

  int isFetching([QueryFilters filters = const QueryFilters()]) => queryCache
      .findAll(filters)
      .where((query) => query.state.fetchStatus == FetchStatus.fetching)
      .length;

  int isMutating([MutationFilters filters = const MutationFilters()]) =>
      mutationCache
          .findAll(filters)
          .where((mutation) => mutation.state.status == MutationStatus.pending)
          .length;

  /// The cached data under [queryKey], or `null` if there is none.
  ///
  /// Throws [QueryDataTypeError] if the entry holds a different type.
  TQueryData? getQueryData<TQueryData>(QueryKey queryKey) {
    final query = queryCache.get<TQueryData>(queryKey);
    return query != null && query.state.hasData ? query.state.data : null;
  }

  QueryState<TQueryData>? getQueryState<TQueryData>(QueryKey queryKey) =>
      queryCache.get<TQueryData>(queryKey)?.state;

  List<(QueryKey, TQueryData?)> getQueriesData<TQueryData>(
    QueryFilters filters,
  ) =>
      queryCache
          .findAll(filters)
          .map(
            (query) => (
              query.queryKey,
              query is Query<TQueryData> && query.state.hasData
                  ? query.state.data
                  : null,
            ),
          )
          .toList();

  // ------------------------------------------------------------- writing

  /// Writes [data] into the cache, creating the entry if needed.
  TQueryData setQueryData<TQueryData>(
    QueryKey queryKey,
    TQueryData data, {
    DateTime? updatedAt,
  }) {
    final query = queryCache.build<TQueryData>(
      this,
      defaultQueryOptions<TQueryData>(
        QueryOptions<TQueryData>(queryKey: queryKey),
      ),
    );
    return query.setData(data, updatedAt: updatedAt, manual: true);
  }

  /// Updates the cached data under [queryKey].
  ///
  /// Split from [setQueryData] because Dart cannot overload on "a value or a
  /// function" (https://github.com/KoTTi97/flutter_query/issues/17).
  /// Returning `null` from [updater] leaves the cache untouched.
  TQueryData? updateQueryData<TQueryData>(
    QueryKey queryKey,
    TQueryData? Function(TQueryData? previous) updater, {
    DateTime? updatedAt,
  }) {
    final existing = queryCache.get<TQueryData>(queryKey);
    final previous =
        existing != null && existing.state.hasData ? existing.state.data : null;
    final next = updater(previous);
    if (next == null) {
      return null;
    }
    return setQueryData<TQueryData>(queryKey, next, updatedAt: updatedAt);
  }

  List<(QueryKey, TQueryData?)> updateQueriesData<TQueryData>(
    QueryFilters filters,
    TQueryData? Function(TQueryData? previous) updater, {
    DateTime? updatedAt,
  }) =>
      notifyManager.batch(
        () => queryCache
            .findAll(filters)
            .map(
              (query) => (
                query.queryKey,
                updateQueryData<TQueryData>(
                  query.queryKey,
                  updater,
                  updatedAt: updatedAt,
                ),
              ),
            )
            .toList(),
      );

  // ---------------------------------------------------------- operations

  Future<void> cancelQueries({
    QueryFilters filters = const QueryFilters(),
    bool revert = true,
    bool silent = true,
  }) async {
    await Future.wait<void>(
      queryCache
          .findAll(filters)
          .map((query) => query.cancel(revert: revert, silent: silent)),
    );
  }

  void removeQueries([QueryFilters filters = const QueryFilters()]) =>
      notifyManager.batch(() {
        for (final query in queryCache.findAll(filters)) {
          queryCache.remove(query);
        }
      });

  Future<void> resetQueries([
    QueryFilters filters = const QueryFilters(),
  ]) async {
    final refetches = notifyManager.batch(() {
      final futures = <Future<void>>[];
      for (final query in queryCache.findAll(filters)) {
        query.reset();
        if (query.isActive()) {
          futures.add(query.fetch().then((_) {}).catchError((Object _) {}));
        }
      }
      return futures;
    });
    await Future.wait(refetches);
  }

  /// Marks matching queries stale and refetches the active ones.
  Future<void> invalidateQueries({
    QueryFilters filters = const QueryFilters(),
    bool refetchActive = true,
  }) async {
    final refetches = notifyManager.batch(() {
      final futures = <Future<void>>[];
      for (final query in queryCache.findAll(filters)) {
        query.invalidate();
        if (refetchActive && query.isActive()) {
          futures.add(
            query
                .fetch(
                    fetchOptions:
                        const FetchOptions<Never>(cancelRefetch: false))
                .then((_) {})
                .catchError((Object _) {}),
          );
        }
      }
      return futures;
    });
    await Future.wait(refetches);
  }

  Future<void> refetchQueries({
    QueryFilters filters = const QueryFilters(),
    bool cancelRefetch = true,
  }) async {
    final refetches = notifyManager.batch(() {
      return queryCache
          .findAll(filters)
          .map(
            (query) => query
                .fetch(
                  fetchOptions:
                      FetchOptions<Never>(cancelRefetch: cancelRefetch),
                )
                .then((_) {})
                .catchError((Object _) {}),
          )
          .toList();
    });
    await Future.wait(refetches);
  }

  /// Fetches and caches, completing with the data.
  Future<TQueryData> fetchQuery<TQueryData>(
    QueryOptions<TQueryData> options,
  ) {
    final defaulted = defaultQueryOptions<TQueryData>(options);
    final query = queryCache.build<TQueryData>(this, defaulted);

    if (query.isStaleByTime(defaulted.staleTime.resolve(query))) {
      return query.fetch(options: defaulted);
    }
    return Future<TQueryData>.value(query.state.data as TQueryData);
  }

  /// Fetches without surfacing errors — for warming the cache.
  Future<void> prefetchQuery<TQueryData>(QueryOptions<TQueryData> options) =>
      fetchQuery<TQueryData>(options).then((_) {}).catchError((Object _) {});

  /// The cached data if it is fresh, otherwise a fetch.
  Future<TQueryData> ensureQueryData<TQueryData>(
    QueryOptions<TQueryData> options,
  ) {
    final defaulted = defaultQueryOptions<TQueryData>(options);
    final query = queryCache.build<TQueryData>(this, defaulted);
    if (query.state.hasData) {
      return Future<TQueryData>.value(query.state.data as TQueryData);
    }
    return fetchQuery<TQueryData>(options);
  }

  Future<void> resumePausedMutations() => mutationCache.resumePaused();

  void clear() {
    queryCache.clear();
    mutationCache.clear();
  }

  // ------------------------------------------------------------ defaults

  DefaultOptions getDefaultOptions() => _defaultOptions;

  void setDefaultOptions(DefaultOptions options) => _defaultOptions = options;

  /// Defaults for every query whose key starts with [queryKey].
  void setQueryDefaults(QueryKey queryKey, QueryDefaults defaults) =>
      _queryDefaults[queryKey] = defaults;

  /// The registered defaults matching [queryKey], merged in registration
  /// order.
  QueryDefaults? getQueryDefaults(QueryKey queryKey) {
    QueryDefaults? merged;
    var matches = 0;
    for (final entry in _queryDefaults.entries) {
      if (queryKey.matches(entry.key)) {
        matches++;
        merged = merged == null ? entry.value : merged.mergedWith(entry.value);
      }
    }
    assert(
      matches <= 1,
      'Several query defaults match $queryKey. They are merged in registration '
      'order, which is rarely what you want — register one prefix per query '
      'family instead.',
    );
    return merged;
  }

  void setMutationDefaults(QueryKey mutationKey, MutationDefaults defaults) =>
      _mutationDefaults[mutationKey] = defaults;

  MutationDefaults? getMutationDefaults(QueryKey mutationKey) {
    MutationDefaults? merged;
    for (final entry in _mutationDefaults.entries) {
      if (mutationKey.matches(entry.key)) {
        merged = merged == null ? entry.value : merged.mergedWith(entry.value);
      }
    }
    return merged;
  }

  /// Resolves [options] against the client and key defaults.
  DefaultedQueryOptions<TQueryData> defaultQueryOptions<TQueryData>(
    QueryOptions<TQueryData> options,
  ) {
    final queryKey = options.queryKey;
    if (queryKey == null) {
      throw ArgumentError('QueryOptions.queryKey is required to build a query');
    }
    final defaults = (_defaultOptions.queries ?? const QueryDefaults())
        .mergedWith(getQueryDefaults(queryKey));

    return DefaultedQueryOptions<TQueryData>(
      queryKey: queryKey,
      queryFn: options.queryFn,
      enabled: options.enabled ?? defaults.enabled ?? Enabled.yes,
      staleTime: options.staleTime ?? defaults.staleTime ?? StaleTime.zero,
      gcTime: options.gcTime ?? defaults.gcTime ?? GcTime.defaultValue,
      retry: options.retry ?? defaults.retry ?? const RetryTimes(3),
      retryDelay:
          options.retryDelay ?? defaults.retryDelay ?? RetryDelay.defaultValue,
      networkMode:
          options.networkMode ?? defaults.networkMode ?? NetworkMode.online,
      initialData: options.initialData,
      initialDataUpdatedAt: options.initialDataUpdatedAt,
      structuralSharing: options.structuralSharing,
      meta: options.meta ?? defaults.meta,
      behavior: options.behavior,
    );
  }

  /// Resolves observer options against the client and key defaults.
  DefaultedQueryObserverOptions<TQueryData, TData>
      defaultQueryObserverOptions<TQueryData, TData>(
    QueryObserverOptions<TQueryData, TData> options,
  ) {
    final base = defaultQueryOptions<TQueryData>(options);
    final queryDefaults = (_defaultOptions.queries ?? const QueryDefaults())
        .mergedWith(getQueryDefaults(base.queryKey));

    return DefaultedQueryObserverOptions<TQueryData, TData>(
      queryKey: base.queryKey,
      queryFn: base.queryFn,
      enabled: base.enabled,
      staleTime: base.staleTime,
      gcTime: base.gcTime,
      retry: base.retry,
      retryDelay: base.retryDelay,
      networkMode: base.networkMode,
      initialData: base.initialData,
      initialDataUpdatedAt: base.initialDataUpdatedAt,
      structuralSharing: base.structuralSharing,
      meta: base.meta,
      behavior: base.behavior,
      retryOnMount: options.retryOnMount ?? queryDefaults.retryOnMount ?? true,
      select: options.select,
      placeholderData: options.placeholderData,
      refetchOnMount: options.refetchOnMount ??
          queryDefaults.refetchOnMount ??
          RefetchOn.ifStale,
      refetchOnWindowFocus: options.refetchOnWindowFocus ??
          queryDefaults.refetchOnWindowFocus ??
          RefetchOn.ifStale,
      refetchOnReconnect: options.refetchOnReconnect ??
          queryDefaults.refetchOnReconnect ??
          RefetchOn.ifStale,
      refetchInterval: options.refetchInterval ??
          queryDefaults.refetchInterval ??
          RefetchInterval.off,
      refetchIntervalInBackground: options.refetchIntervalInBackground ??
          queryDefaults.refetchIntervalInBackground ??
          false,
    );
  }

  /// Resolves mutation options against the client and key defaults.
  DefaultedMutationOptions<TData, TVariables, TOnMutateResult>
      defaultMutationOptions<TData, TVariables, TOnMutateResult>(
    MutationOptions<TData, TVariables, TOnMutateResult> options,
  ) {
    final mutationKey = options.mutationKey;
    final defaults =
        (_defaultOptions.mutations ?? const MutationDefaults()).mergedWith(
      mutationKey == null ? null : getMutationDefaults(mutationKey),
    );

    return DefaultedMutationOptions<TData, TVariables, TOnMutateResult>(
      mutationKey: mutationKey,
      mutationFn: options.mutationFn,
      retry: options.retry ?? defaults.retry ?? RetryPolicy.never,
      retryDelay:
          options.retryDelay ?? defaults.retryDelay ?? RetryDelay.defaultValue,
      networkMode:
          options.networkMode ?? defaults.networkMode ?? NetworkMode.online,
      gcTime: options.gcTime ?? defaults.gcTime ?? GcTime.defaultValue,
      scope: options.scope ?? defaults.scope,
      meta: options.meta ?? defaults.meta,
      onMutate: options.onMutate,
      onSuccess: options.onSuccess,
      onError: options.onError,
      onSettled: options.onSettled,
    );
  }

  /// A one-off observer for [options]. The caller owns its lifetime.
  QueryObserver<TQueryData, TData> observe<TQueryData, TData>(
    QueryObserverOptions<TQueryData, TData> options,
  ) =>
      QueryObserver<TQueryData, TData>(this, options);
}
