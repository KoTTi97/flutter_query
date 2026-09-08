import 'dart:async';

import 'filters.dart';
import 'focus_manager.dart';
import 'mutation_cache.dart';
import 'mutation_observer.dart';
import 'mutation_options.dart';
import 'mutation_state.dart';
import 'notify_manager.dart';
import 'online_manager.dart';
import 'option_values.dart';
import 'query.dart';
import 'query_cache.dart';
import 'query_key.dart';
import 'query_observer.dart';
import 'query_options.dart';
import 'query_state.dart';

/// The imperative face of the cache.
///
/// Everything here is a one-off command — fetch this, invalidate that, write
/// this data — as opposed to [QueryObserver], which is the reactive face. Event
/// handlers and mutation callbacks use the client; widgets use observers.
///
/// The client also owns the option-defaulting chain: library fallbacks, then
/// client-wide defaults, then any key defaults registered with
/// [setQueryDefaults], then what the caller passed.
class QueryClient implements ObserverClient, MutationObserverClient {
  QueryClient({
    QueryCache? queryCache,
    MutationCache? mutationCache,
    this.defaultOptions = QueryDefaults.empty,
    this.defaultMutationOptionsBag = const MutationDefaults(),
  })  : _queryCache = queryCache ?? QueryCache(),
        _mutationCache = mutationCache ?? MutationCache();

  final QueryCache _queryCache;
  final MutationCache _mutationCache;

  /// Key defaults in registration order — later registrations win, so the
  /// iteration order of this map is load-bearing.
  final Map<QueryKey, QueryDefaults> _queryDefaults =
      <QueryKey, QueryDefaults>{};

  final Map<MutationKey, MutationDefaults> _mutationDefaults =
      <MutationKey, MutationDefaults>{};

  int _mountCount = 0;
  void Function()? _unsubscribeFocus;
  void Function()? _unsubscribeOnline;

  @override
  QueryCache get queryCache => _queryCache;

  @override
  MutationCache get mutationCache => _mutationCache;

  /// Defaults applied to every query, before any key defaults.
  QueryDefaults defaultOptions;

  /// Defaults applied to every mutation, before any key defaults.
  MutationDefaults defaultMutationOptionsBag;

  // --- Lifecycle ------------------------------------------------------------

  /// Starts reacting to focus and connectivity.
  ///
  /// Ref-counted, so nesting scopes is safe: only the first [mount] subscribes
  /// and only the matching [unmount] tears down.
  void mount() {
    _mountCount++;
    if (_mountCount != 1) {
      return;
    }

    _unsubscribeFocus = focusManager.subscribe((focused) async {
      if (focused) {
        // Order matters: a write that was queued offline should land before
        // the reads that would otherwise overwrite the screen with stale data.
        await resumePausedMutations();
        _queryCache.onFocus();
      }
    });

    _unsubscribeOnline = onlineManager.subscribe((online) async {
      if (online) {
        await resumePausedMutations();
        _queryCache.onOnline();
      }
    });
  }

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

  /// Resumes mutations that paused while offline.
  ///
  /// Only while online: resuming them offline would just pause them again.
  Future<void> resumePausedMutations() {
    if (onlineManager.isOnline) {
      return _mutationCache.resumePausedMutations();
    }
    return Future<void>.value();
  }

  // --- Reading --------------------------------------------------------------

  /// How many queries matching [filters] are fetching right now.
  int isFetching({QueryFilters filters = const QueryFilters()}) => _queryCache
      .findAll(filters.copyWith(fetchStatus: FetchStatus.fetching))
      .length;

  /// How many mutations matching [filters] are running right now.
  int isMutating({MutationFilters filters = const MutationFilters()}) =>
      _mutationCache
          .findAll(filters.copyWith(status: MutationStatus.pending))
          .length;

  /// The data cached under [queryKey], or null if there is none.
  ///
  /// A snapshot, not a subscription — use a [QueryObserver] to follow changes.
  TQueryData? getQueryData<TQueryData>(QueryKey queryKey) =>
      _queryCache.get<TQueryData>(queryKey)?.state.data;

  QueryState<TQueryData>? getQueryState<TQueryData>(QueryKey queryKey) =>
      _queryCache.get<TQueryData>(queryKey)?.state;

  /// The key and data of every query matching [filters] — how one cache entry
  /// seeds another, as when a list response fills in the per-item entries.
  List<(QueryKey, TQueryData?)> getQueriesData<TQueryData>(
    QueryFilters filters,
  ) =>
      _queryCache
          .findAll(filters)
          .map((query) => (query.queryKey, query.state.data as TQueryData?))
          .toList();

  // --- Writing --------------------------------------------------------------

  /// Writes data into the cache, creating the entry if needed.
  ///
  /// [updater] receives whatever is cached now (null if nothing is) and returns
  /// the replacement. **Returning null aborts the write** — that is how an
  /// optimistic update declines to act on an entry it has no basis to change,
  /// and it is why cached values are non-null by invariant.
  TQueryData? setQueryData<TQueryData>(
    QueryKey queryKey,
    TQueryData? Function(TQueryData? previous) updater, {
    DateTime? updatedAt,
  }) {
    final existing = _queryCache.get<TQueryData>(queryKey);
    final data = updater(existing?.state.data);
    if (data == null) {
      return null;
    }

    final options = defaultQueryOptions<TQueryData, TQueryData>(
      QueryObserverOptions<TQueryData, TQueryData>(queryKey: queryKey),
    );
    return _queryCache
        .build<TQueryData>(options)
        .setData(data, updatedAt: updatedAt, manual: true);
  }

  /// [setQueryData] across every query matching [filters], as one batch so
  /// observers see a single update.
  List<(QueryKey, TQueryData?)> setQueriesData<TQueryData>(
    QueryFilters filters,
    TQueryData? Function(TQueryData? previous) updater, {
    DateTime? updatedAt,
  }) {
    return notifyManager.batch(
      () => _queryCache
          .findAll(filters)
          .map(
            (query) => (
              query.queryKey,
              setQueryData<TQueryData>(
                query.queryKey,
                updater,
                updatedAt: updatedAt,
              ),
            ),
          )
          .toList(),
    );
  }

  // --- Cache commands -------------------------------------------------------

  void removeQueries({QueryFilters filters = const QueryFilters()}) {
    notifyManager.batch(() {
      for (final query in _queryCache.findAll(filters)) {
        _queryCache.remove(query);
      }
    });
  }

  /// Returns matching queries to their initial state, then refetches the active
  /// ones.
  Future<void> resetQueries({
    QueryFilters filters = const QueryFilters(),
    bool throwOnError = false,
  }) {
    return notifyManager.batch(() {
      final matched = _queryCache.findAll(filters);
      // Snapshot the set: resetting can change what the filter would match.
      final toRefetch = Set<Query<Object?>>.identity()..addAll(matched);

      for (final query in matched) {
        query.reset();
      }

      return refetchQueries(
        filters: QueryFilters(
          type: QueryTypeFilter.active,
          predicate: toRefetch.contains,
        ),
        throwOnError: throwOnError,
      );
    });
  }

  /// Cancels in-flight fetches. Never fails: the caller wants them stopped, not
  /// a report of how each one ended.
  ///
  /// [revert] restores the state each query held before its fetch started,
  /// which is what makes a cancel invisible rather than leaving a half-updated
  /// screen.
  Future<void> cancelQueries({
    QueryFilters filters = const QueryFilters(),
    bool revert = true,
    bool silent = false,
  }) {
    final futures = notifyManager.batch(
      () => _queryCache
          .findAll(filters)
          .map((query) => query.cancel(revert: revert, silent: silent))
          .toList(),
    );

    return Future.wait(
      futures,
    ).then((_) {}, onError: (Object _, StackTrace _) {});
  }

  /// Marks matching queries stale and refetches the ones worth refetching.
  ///
  /// This is the normal follow-up to a mutation: invalidate the keys the write
  /// touched and let anything on screen refresh itself.
  Future<void> invalidateQueries({
    QueryFilters filters = const QueryFilters(),
    QueryRefetchType? refetchType,
    bool cancelRefetch = true,
    bool throwOnError = false,
  }) {
    return notifyManager.batch(() {
      for (final query in _queryCache.findAll(filters)) {
        query.invalidate();
      }

      if (refetchType == QueryRefetchType.none) {
        return Future<void>.value();
      }

      // Default to refetching only what is on screen; an inactive query will
      // refetch on its own when something starts watching it again.
      final type = switch (refetchType) {
        QueryRefetchType.all => QueryTypeFilter.all,
        QueryRefetchType.active => QueryTypeFilter.active,
        QueryRefetchType.inactive => QueryTypeFilter.inactive,
        QueryRefetchType.none || null => filters.type ?? QueryTypeFilter.active,
      };

      return refetchQueries(
        filters: filters.copyWith(type: type),
        cancelRefetch: cancelRefetch,
        throwOnError: throwOnError,
      );
    });
  }

  /// Refetches matching queries and completes when they have all settled.
  ///
  /// Queries that are disabled or pinned static are skipped, and a query paused
  /// for connectivity contributes an already-completed future — otherwise
  /// awaiting this offline would hang forever.
  Future<void> refetchQueries({
    QueryFilters filters = const QueryFilters(),
    bool cancelRefetch = true,
    bool throwOnError = false,
  }) {
    final futures = notifyManager.batch(
      () => _queryCache
          .findAll(filters)
          .where((query) => !query.isDisabled() && !query.isStatic())
          .map((query) {
        var future = query.fetch(cancelRefetch: cancelRefetch);
        if (!throwOnError) {
          future = future.then<Object?>(
            (value) => value,
            onError: (Object _, StackTrace _) => null,
          );
        }

        if (query.state.fetchStatus == FetchStatus.paused) {
          future.ignore();
          return Future<Object?>.value();
        }
        return future;
      }).toList(),
    );

    return Future.wait(futures).then((_) {});
  }

  // --- One-off fetches ------------------------------------------------------

  /// Fetches and returns the data, reusing the cache entry if it is still
  /// fresh.
  ///
  /// Unlike an observer, this does not retry by default: a caller awaiting a
  /// single answer usually wants the failure now rather than after a backoff.
  Future<TData> query<TQueryData, TData>(
    QueryObserverOptions<TQueryData, TData> options,
  ) async {
    final defaulted = _oneOffOptions(options);
    final query = _queryCache.build<TQueryData>(defaulted);

    final data = query.isStaleByTime(defaulted.staleTime)
        ? await query.fetch(options: defaulted)
        : query.state.data as TQueryData;

    final select = defaulted.select;
    return select != null ? select(data) : data as TData;
  }

  /// [query] without a `select` step.
  Future<TQueryData> fetchQuery<TQueryData>(
    QueryObserverOptions<TQueryData, TQueryData> options,
  ) =>
      query(options);

  /// Warms the cache and swallows failures — a prefetch that fails is not the
  /// caller's problem, the eventual observer will surface it.
  Future<void> prefetchQuery<TQueryData>(
    QueryObserverOptions<TQueryData, TQueryData> options,
  ) =>
      fetchQuery(options).then((_) {}, onError: (Object _, StackTrace _) {});

  // --- Defaults -------------------------------------------------------------

  /// Registers defaults for every query whose key starts with [queryKey].
  void setQueryDefaults(QueryKey queryKey, QueryDefaults defaults) {
    _queryDefaults[queryKey] = defaults;
  }

  /// Every registered default whose key is a prefix of [queryKey], merged in
  /// registration order.
  ///
  /// Registrations are not ranked by specificity: a later general default beats
  /// an earlier specific one, matching upstream.
  QueryDefaults getQueryDefaults(QueryKey queryKey) {
    var result = QueryDefaults.empty;
    for (final entry in _queryDefaults.entries) {
      if (entry.key.isPrefixOf(queryKey)) {
        result = result.mergedWith(entry.value);
      }
    }
    return result;
  }

  @override
  DefaultedQueryObserverOptions<TQueryData, TData>
      defaultQueryOptions<TQueryData, TData>(
              QueryObserverOptions<TQueryData, TData> options) =>
          resolveQueryObserverOptions(
            options,
            defaults: _defaultsFor(options.queryKey),
          );

  QueryDefaults _defaultsFor(QueryKey queryKey) =>
      defaultOptions.mergedWith(getQueryDefaults(queryKey));

  /// Registers defaults for every mutation whose key starts with [mutationKey].
  void setMutationDefaults(MutationKey mutationKey, MutationDefaults defaults) {
    _mutationDefaults[mutationKey] = defaults;
  }

  /// Every registered default whose key is a prefix of [mutationKey], merged in
  /// registration order.
  MutationDefaults getMutationDefaults(MutationKey mutationKey) {
    var result = const MutationDefaults();
    for (final entry in _mutationDefaults.entries) {
      if (entry.key.isPrefixOf(mutationKey)) {
        result = mergeMutationDefaults(result, entry.value);
      }
    }
    return result;
  }

  @override
  DefaultedMutationOptions<TData, TVariables, TOnMutateResult>
      defaultMutationOptions<TData, TVariables, TOnMutateResult>(
    MutationOptions<TData, TVariables, TOnMutateResult> options,
  ) {
    final mutationKey = options.mutationKey;
    final defaults = mutationKey == null
        ? defaultMutationOptionsBag
        : mergeMutationDefaults(
            defaultMutationOptionsBag,
            getMutationDefaults(mutationKey),
          );
    return resolveMutationOptions(options, defaults: defaults);
  }

  /// Defaulting for a single awaited fetch, which does not retry unless
  /// something asked it to.
  DefaultedQueryObserverOptions<TQueryData, TData>
      _oneOffOptions<TQueryData, TData>(
          QueryObserverOptions<TQueryData, TData> options) {
    var defaults = _defaultsFor(options.queryKey);
    if (options.retry == null && defaults.retry == null) {
      defaults = defaults.mergedWith(
        const QueryDefaults(retry: RetryOption.never),
      );
    }
    return resolveQueryObserverOptions(options, defaults: defaults);
  }

  /// Empties both caches.
  void clear() {
    _queryCache.clear();
    _mutationCache.clear();
  }
}
