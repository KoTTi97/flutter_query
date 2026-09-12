/// Port of `query-core/src/queryClient.ts` at upstream `50680b98c`.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'filters.dart';
import 'focus_manager.dart';
import 'infinite_query.dart';
import 'infinite_query_observer.dart';
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
/// express "options for any data type", so defaults carry the options that do
/// not mention the data type, plus the two that are worth erasing for
/// ([queryFn] and [structuralSharing] — a shared fetcher per key prefix is the
/// single most useful default there is). The rest (`initialData`, `select`,
/// `placeholderData`) belongs to a single query and is passed at the call
/// site.
@immutable
class QueryDefaults {
  /// Creates a set of defaults; every field is optional, and an unset one
  /// defers to the next layer down (the client-wide defaults, then upstream's
  /// built-in values).
  const QueryDefaults({
    this.queryFn,
    this.structuralSharing,
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

  /// A fetcher for every query this default covers.
  ///
  /// Erased to `Object?`, because one default serves every data type under a
  /// key prefix; `QueryClient.defaultQueryOptions` adapts it to the call site
  /// and throws [QueryDataTypeError] if it hands back the wrong type — the
  /// same bargain the cache's typed reads make
  /// (https://github.com/KoTTi97/flutter_query/issues/7).
  final QueryFn<Object?>? queryFn;

  /// Erased for the same reason as [queryFn]. `noStructuralSharing()` is
  /// recognised here too, and reaches each query as its own typed opt-out —
  /// `select` output included (pre-release review, 2026-09-12, F4).
  final Object? Function(Object? previous, Object? next)? structuralSharing;

  /// Default for `enabled`: whether queries under this default fetch on their
  /// own.
  final Enabled? enabled;

  /// Default for `staleTime`: how long fetched data counts as fresh.
  final StaleTime? staleTime;

  /// Default for `gcTime`: how long an unobserved query stays in the cache.
  final GcTime? gcTime;

  /// Default for `retry`: whether and how often a failed fetch is retried.
  final RetryPolicy? retry;

  /// Default for `retryDelay`: the backoff between retries.
  final RetryDelay? retryDelay;

  /// Default for `retryOnMount`: whether a query in error state is retried
  /// when a new observer subscribes. `true` when unset here too.
  final bool? retryOnMount;

  /// Default for `networkMode`: when a fetch may run relative to the online
  /// state.
  final NetworkMode? networkMode;

  /// Default for `refetchOnMount`: whether a subscribing observer refetches
  /// data it already has.
  final RefetchOn? refetchOnMount;

  /// Default for `refetchOnWindowFocus`: whether the app returning to the
  /// foreground refetches.
  final RefetchOn? refetchOnWindowFocus;

  /// Default for `refetchOnReconnect`: whether the device coming back online
  /// refetches.
  final RefetchOn? refetchOnReconnect;

  /// Default for `refetchInterval`: how often to poll, if at all.
  final RefetchInterval? refetchInterval;

  /// Default for `refetchIntervalInBackground`: whether polling continues while
  /// the app is not in the foreground.
  final bool? refetchIntervalInBackground;

  /// Default for `meta`: opaque data handed to the query function's context and
  /// readable off the query.
  final Object? meta;

  /// These defaults with [other]'s laid over them, field by field: a field
  /// [other] sets wins, one it leaves `null` falls through to this. `null`
  /// [other] returns this unchanged.
  QueryDefaults mergedWith(QueryDefaults? other) {
    if (other == null) return this;
    return QueryDefaults(
      queryFn: other.queryFn ?? queryFn,
      structuralSharing: other.structuralSharing ?? structuralSharing,
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

  // Field by field, functions by identity — like the `Defaulted*` options,
  // and for the same reason: a `setQueryDefaults` with an equal value must
  // not read as a change.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryDefaults &&
          other.queryFn == queryFn &&
          other.structuralSharing == structuralSharing &&
          other.enabled == enabled &&
          other.staleTime == staleTime &&
          other.gcTime == gcTime &&
          other.retry == retry &&
          other.retryDelay == retryDelay &&
          other.retryOnMount == retryOnMount &&
          other.networkMode == networkMode &&
          other.refetchOnMount == refetchOnMount &&
          other.refetchOnWindowFocus == refetchOnWindowFocus &&
          other.refetchOnReconnect == refetchOnReconnect &&
          other.refetchInterval == refetchInterval &&
          other.refetchIntervalInBackground == refetchIntervalInBackground &&
          other.meta == meta;

  @override
  int get hashCode => Object.hash(
        queryFn,
        structuralSharing,
        enabled,
        staleTime,
        gcTime,
        retry,
        retryDelay,
        retryOnMount,
        networkMode,
        refetchOnMount,
        refetchOnWindowFocus,
        refetchOnReconnect,
        refetchInterval,
        refetchIntervalInBackground,
        meta,
      );
}

/// Type-agnostic mutation defaults.
@immutable
class MutationDefaults {
  /// Creates a set of defaults; every field is optional, and an unset one
  /// defers to the next layer down.
  const MutationDefaults({
    this.mutationFn,
    this.retry,
    this.retryDelay,
    this.networkMode,
    this.gcTime,
    this.scope,
    this.meta,
  });

  /// A default mutation function for every mutation under this key.
  ///
  /// Erased for the same reason as [QueryDefaults.queryFn]: one default serves
  /// every variable and result type under a key prefix.
  final MutationFn<Object?, Object?>? mutationFn;

  /// Default for `retry`: whether and how often a failed mutation is retried.
  /// Upstream's built-in is no retries at all.
  final RetryPolicy? retry;

  /// Default for `retryDelay`: the backoff between retries.
  final RetryDelay? retryDelay;

  /// Default for `networkMode`: when a mutation may run relative to the online
  /// state.
  final NetworkMode? networkMode;

  /// Default for `gcTime`: how long a settled, unobserved mutation stays in
  /// the cache.
  final GcTime? gcTime;

  /// Default for `scope`: mutations sharing a scope run one at a time, in
  /// submission order.
  final MutationScope? scope;

  /// Default for `meta`: opaque data readable off the mutation.
  final Object? meta;

  /// These defaults with [other]'s laid over them, field by field; a `null`
  /// [other] returns this unchanged.
  MutationDefaults mergedWith(MutationDefaults? other) {
    if (other == null) return this;
    return MutationDefaults(
      mutationFn: other.mutationFn ?? mutationFn,
      retry: other.retry ?? retry,
      retryDelay: other.retryDelay ?? retryDelay,
      networkMode: other.networkMode ?? networkMode,
      gcTime: other.gcTime ?? gcTime,
      scope: other.scope ?? scope,
      meta: other.meta ?? meta,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MutationDefaults &&
          other.mutationFn == mutationFn &&
          other.retry == retry &&
          other.retryDelay == retryDelay &&
          other.networkMode == networkMode &&
          other.gcTime == gcTime &&
          other.scope == scope &&
          other.meta == meta;

  @override
  int get hashCode => Object.hash(
        mutationFn,
        retry,
        retryDelay,
        networkMode,
        gcTime,
        scope,
        meta,
      );
}

/// Client-wide defaults.
@immutable
class DefaultOptions {
  /// Creates the client-wide defaults; either half may be left out.
  const DefaultOptions({this.queries, this.mutations});

  /// Applied to every query the client resolves, beneath any key-specific
  /// [QueryClient.setQueryDefaults].
  final QueryDefaults? queries;

  /// Applied to every mutation the client resolves, beneath any key-specific
  /// [QueryClient.setMutationDefaults].
  final MutationDefaults? mutations;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DefaultOptions &&
          other.queries == queries &&
          other.mutations == mutations;

  @override
  int get hashCode => Object.hash(queries, mutations);
}

/// The cache's front door: everything imperative happens here.
class QueryClient {
  /// Creates a client. Every collaborator is optional: a fresh [QueryCache],
  /// [MutationCache], [AppFocusManager], [OnlineManager] and [NotifyManager]
  /// are made when none is passed, and [defaultOptions] starts empty. Call
  /// [mount] to have it react to focus and connectivity, and [clear] when it
  /// is done — a client owns `gcTime` timers that outlive any widget tree.
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
        // One per client, like the other managers: the Flutter binding
        // installs its scheduler on the client's manager, and two clients
        // sharing one would hand that scheduler back and forth in mount
        // order. Pass `NotifyManager.shared` to batch across clients.
        notifyManager = notifyManager ?? NotifyManager(),
        _defaultOptions = defaultOptions ?? const DefaultOptions();

  /// Every query, keyed by [QueryKey]. Subscribe to it for cache events; most
  /// reads and writes go through the client's own methods instead.
  final QueryCache queryCache;

  /// Every mutation, in submission order. Subscribe to it for cache events.
  final MutationCache mutationCache;

  /// Owned by the client rather than global, so tests are hermetic
  /// (https://github.com/KoTTi97/flutter_query/issues/19).
  final AppFocusManager focusManager;

  /// Whether the device is believed to be online. The Flutter binding drives
  /// its `setOnline` from an optional connectivity stream; a [mount]ed client
  /// listens to it and resumes paused mutations and queries on reconnect.
  final OnlineManager onlineManager;

  /// Batches this client's listener notifications. The Flutter binding
  /// installs a build-phase-aware scheduler on it; pass [NotifyManager.shared]
  /// to batch across clients.
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
  ///
  /// Without it nothing reacts to the app returning to the foreground or the
  /// device coming back online: no `refetchOnWindowFocus`, no
  /// `refetchOnReconnect`, no resuming of paused mutations — and a [query]
  /// under [NetworkMode.online] that paused offline waits for a reconnect
  /// only if the client is mounted. The Flutter binding mounts the client it
  /// is given; a pure-Dart user calls this once and [unmount] when done.
  ///
  /// On each focus or reconnect the paused mutations are resumed first and
  /// the queries wait for *all* of them to settle — scope queues included —
  /// before `queryCache.onFocus` / `onOnline` runs, so a refetch cannot
  /// overtake the mutation it was meant to reflect. Upstream does the same.
  /// The price is that a mutation that never settles blocks the query side's
  /// focus and reconnect refetches for as long as it runs.
  void mount() {
    _mountCount++;
    if (_mountCount != 1) {
      return;
    }

    _unsubscribeFocus = focusManager.subscribe((focused) {
      if (focused) {
        // Capture before awaiting mutations: later focus events may change it.
        final refetch = focusManager.shouldRefetchOnFocus;
        _resumeThen(() => queryCache.onFocus(refetchQueries: refetch)).ignore();
      }
    });

    _unsubscribeOnline = onlineManager.subscribe((online) {
      if (online) {
        _resumeThen(queryCache.onOnline).ignore();
      }
    });
  }

  /// Paused mutations go first and the queries wait for them: a refetch that
  /// overtook the mutation it was meant to reflect would show the server's
  /// pre-mutation state. Nobody awaits this future — the managers' listeners
  /// are `void` — so a throw is reported to the zone here rather than left
  /// to surface as an unhandled rejection of a future nobody holds.
  Future<void> _resumeThen(void Function() then) async {
    try {
      await resumePausedMutations();
      then();
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  /// Stops listening. Balanced with [mount].
  void unmount() {
    if (_mountCount == 0) {
      // Never below zero. An unmount without a matching mount used to leave
      // the count at -1, and the next `mount()` then took it to 0 and
      // subscribed to nothing: focus and reconnect refetching off for the
      // life of the client, silently (eighth review, 2026-09-10).
      return;
    }
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

  /// How many queries matching [filters] are fetching right now — actually
  /// fetching, not paused. Every query when the filters are empty. Upstream's
  /// `isFetching`.
  int isFetching({QueryFilters filters = const QueryFilters()}) => queryCache
      .findAll(filters: filters)
      .where((query) => query.state.fetchStatus == FetchStatus.fetching)
      .length;

  /// How many mutations matching [filters] are pending right now. Every
  /// mutation when the filters are empty. Upstream's `isMutating`.
  int isMutating({MutationFilters filters = const MutationFilters()}) =>
      mutationCache
          .findAll(filters: filters)
          .where((mutation) => mutation.state.status == MutationStatus.pending)
          .length;

  /// The cached data under [queryKey], or `null` if there is none.
  ///
  /// Throws [QueryDataTypeError] if the entry holds a different type.
  TQueryData? getQueryData<TQueryData>(QueryKey queryKey) {
    final query = queryCache.get<TQueryData>(queryKey);
    return query != null && query.state.hasData ? query.state.data : null;
  }

  /// The cached infinite data under [queryKey], or `null` if absent.
  /// Throws [QueryDataTypeError] when the entry has another data type.
  InfiniteData<TPageData, TPageParam>?
      getInfiniteQueryData<TPageData, TPageParam>(QueryKey queryKey) =>
          getQueryData<InfiniteData<TPageData, TPageParam>>(queryKey);

  /// The full state of the query under [queryKey] — status, fetch status,
  /// timestamps and counters, not just the data — or `null` if there is none.
  /// Throws [QueryDataTypeError] if the entry holds a different type.
  /// Upstream's `getQueryState`.
  QueryState<TQueryData>? getQueryState<TQueryData>(QueryKey queryKey) =>
      queryCache.get<TQueryData>(queryKey)?.state;

  /// The cached data of every matching query, `null` where a query holds
  /// none yet.
  ///
  /// Throws [QueryDataTypeError] if a matching query holds another type, as
  /// [getQueryData] does — a `null` there would read as "nothing cached" and
  /// hide the bug (fourth review, 2026-09-09).
  List<(QueryKey, TQueryData?)> getQueriesData<TQueryData>({
    required QueryFilters filters,
  }) =>
      queryCache.findAll(filters: filters).map((query) {
        if (query.dataType != TQueryData) {
          throw QueryDataTypeError(query.queryKey, TQueryData, query.dataType);
        }
        return (
          query.queryKey,
          query.state.hasData ? query.state.data as TQueryData : null,
        );
      }).toList();

  // ------------------------------------------------------------- writing

  /// Writes [data] into the cache, creating the entry if needed.
  ///
  /// The type argument is inferred from [data], and a value infers its
  /// non-nullable type: `setQueryData(key, 'x')` is a `String` write, which
  /// a query holding `String?` refuses with [QueryDataTypeError]. Name the
  /// query's type — `setQueryData<String?>(key, 'x')` (ninth review,
  /// 2026-09-10, C23).
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

  /// Runs [updater] over every query matching [filters] and returns each key
  /// with what it now holds. A type mismatch anywhere under the filters
  /// throws before anything is written. The filtered twin of
  /// [updateQueryData], upstream's `setQueriesData`.
  ///
  /// The writes run in one [NotifyManager.batch]. Only callbacks submitted
  /// through `schedule` or `batchCalls` are deferred until the batch ends.
  /// Direct observer subscriptions, cache listeners and `onQueryUpdate` run
  /// synchronously for each write.
  List<(QueryKey, TQueryData?)> updateQueriesData<TQueryData>(
    TQueryData? Function(TQueryData? previous) updater, {
    required QueryFilters filters,
    DateTime? updatedAt,
  }) {
    final queries = queryCache.findAll(filters: filters);
    // Checked before anything is written, so a mismatch under the prefix
    // throws with the cache untouched rather than half-updated.
    for (final query in queries) {
      if (query.dataType != TQueryData) {
        throw QueryDataTypeError(query.queryKey, TQueryData, query.dataType);
      }
    }
    return notifyManager.batch(
      () => queries
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
  }

  // ---------------------------------------------------------- operations

  /// Cancels every matching in-flight fetch, completing once they have all
  /// settled.
  ///
  /// [revert] puts each query back to the state it held before the cancelled
  /// fetch — upstream's default too. [silent] cancels without dispatching an
  /// error; it is *not* on by default, because a silent cancel means "a new
  /// fetch is taking over", which is not what an explicit cancel is. A
  /// silently cancelled fetch that nothing replaces is put back to `idle`
  /// rather than left `fetching` forever — see [Query.cancel].
  Future<void> cancelQueries({
    QueryFilters filters = const QueryFilters(),
    bool revert = true,
    bool silent = false,
  }) async {
    // Batched like the other bulk operations (and upstream's): every revert
    // is dispatched inside one transaction.
    final cancels = notifyManager.batch(
      () => queryCache
          .findAll(filters: filters)
          .map((query) => query.cancel(revert: revert, silent: silent))
          .toList(),
    );
    await Future.wait<void>(cancels);
  }

  /// Removes every query matching [filters] from the cache — all of them when
  /// the filters are empty — cancelling their fetches silently. Upstream's
  /// `removeQueries`.
  ///
  /// An observer still attached to a removed query stays on it: it keeps
  /// reporting the removed entry's state, and a later [setQueryData] or
  /// [query] of the same key creates a *new* entry it never sees, until its
  /// next `setOptions` or resubscribe re-resolves the key. For a key with
  /// live observers use [resetQueries], which keeps the entry and puts it
  /// back to its initial state; removal is for keys nobody is watching.
  void removeQueries({QueryFilters filters = const QueryFilters()}) =>
      notifyManager.batch(() {
        for (final query in queryCache.findAll(filters: filters)) {
          queryCache.remove(query);
        }
      });

  /// Puts matching queries back to the state they were created with, then
  /// refetches the active ones.
  ///
  /// `async`, like [cancelQueries] and [refetchQueries]: a throwing filter
  /// predicate fails the returned future rather than throwing out of the
  /// call, so all four bulk operations report the same way. Upstream's
  /// `notifyManager.batch(() => …)` form throws synchronously from a
  /// `Promise`-returning method (pre-release verification, 2026-09-12,
  /// AR-12).
  Future<void> resetQueries({
    QueryFilters filters = const QueryFilters(),
    bool cancelRefetch = true,
  }) async =>
      notifyManager.batch(() {
        // The matched set is captured *before* resetting, because a filter that
        // looks at state (`status: error`, a predicate over `query.state`) no
        // longer matches once the reset has happened.
        final matched = Set<Query<Object?>>.identity()
          ..addAll(queryCache.findAll(filters: filters));
        for (final query in matched) {
          query.reset();
        }
        return refetchQueries(
          filters: QueryFilters(
            type: QueryTypeFilter.active,
            predicate: matched.contains,
          ),
          cancelRefetch: cancelRefetch,
        );
      });

  /// Marks matching queries stale and refetches the ones [refetchType] names,
  /// which defaults to the filter's own type and then to
  /// [QueryTypeFilter.active].
  ///
  /// `async` for the reason [resetQueries] is.
  Future<void> invalidateQueries({
    QueryFilters filters = const QueryFilters(),
    RefetchType? refetchType,
    bool cancelRefetch = true,
  }) async =>
      notifyManager.batch(() {
        // The matched set is captured *before* invalidating, as `resetQueries`
        // does: a filter that looks at state (`stale: false`, a predicate over
        // `query.state.isInvalidated`) no longer matches once the query has
        // been marked, and upstream — which re-runs the same filter for the
        // refetch — then refetched none of the queries it had just invalidated
        // (fifth review, 2026-09-09). Only the `type` is re-evaluated, since
        // `refetchType` may narrow it.
        final matched = Set<Query<Object?>>.identity()
          ..addAll(queryCache.findAll(filters: filters));
        for (final query in matched) {
          query.invalidate();
        }
        if (refetchType == RefetchType.none) {
          return Future<void>.value();
        }
        final type = switch (refetchType) {
          RefetchType.active => QueryTypeFilter.active,
          RefetchType.inactive => QueryTypeFilter.inactive,
          RefetchType.all => QueryTypeFilter.all,
          RefetchType.none || null => filters.type ?? QueryTypeFilter.active,
        };
        return refetchQueries(
          filters: QueryFilters(type: type, predicate: matched.contains),
          cancelRefetch: cancelRefetch,
        );
      });

  /// Refetches every matching query that can actually fetch.
  Future<void> refetchQueries({
    QueryFilters filters = const QueryFilters(),
    bool cancelRefetch = true,
  }) async {
    final refetches = notifyManager.batch(
      () => queryCache
          .findAll(filters: filters)
          // A disabled query has nothing to refetch, and a static one declared
          // itself permanently fresh.
          .where((query) => !query.isDisabled() && !query.isStatic())
          .map((query) {
        final fetch = query
            .fetch(
              fetchOptions: FetchOptions(cancelRefetch: cancelRefetch),
            )
            .then((_) {})
            .catchError((Object _) {});
        // A paused fetch settles whenever the network comes back, which is
        // never in a test and unbounded in an app: do not wait on it.
        return query.state.fetchStatus == FetchStatus.paused
            ? Future<void>.value()
            : fetch;
      }).toList(),
    );
    await Future.wait(refetches);
  }

  /// Fetches and caches [options]'s query, completing with its data.
  ///
  /// The imperative counterpart of an observer: no `enabled`, no refetch
  /// triggers, and — as upstream does — **no retries unless asked for**, since
  /// there is no widget to catch a thrown error and try again.
  ///
  /// Upstream's `fetchQuery`, `prefetchQuery` and `ensureQueryData` are
  /// deprecated in favour of this one method
  /// (https://github.com/KoTTi97/flutter_query/issues/17):
  ///
  /// - to prefetch, ignore the future: `client.query(options).ignore()`;
  /// - to fetch only when nothing is cached, pass
  ///   `staleTime: StaleTime.static`;
  /// - to reshape the result, `await` it and map it — Dart needs no `select`
  ///   here.
  /// With [revalidateIfStale], existing data is returned immediately while a
  /// stale query refreshes in the background. Missing data still awaits the
  /// fetch. Background errors update the cache and its callbacks as usual.
  ///
  /// That last point changes when this call throws: with [revalidateIfStale]
  /// the future fails only when nothing is cached at all. A query holding
  /// stale data completes with that data even when it is in an error state and
  /// even when the background refresh fails too — the error reaches the state
  /// and the cache callbacks, not this caller.
  Future<TQueryData> query<TQueryData>(QueryOptions<TQueryData> options,
      {bool revalidateIfStale = false}) {
    // Resolved once: the scan over the registered defaults runs per call.
    final defaults = _queryDefaultsFor(options.queryKey);
    final defaulted = _defaultQueryOptionsWith<TQueryData>(
      options,
      options.queryKey,
      defaults,
    );
    final query = queryCache.build<TQueryData>(this, defaulted);
    // Capture before fetching: a synchronous fetcher may replace the data.
    final cachedData = query.state.data;
    final returnCached = revalidateIfStale && query.state.hasData;

    if (query.isStaleByTime(defaulted.staleTime)) {
      // Upstream's imperative-path rule — a caller who configured nothing
      // gets no retries — applied to this fetch alone. Upstream writes
      // `retry: 0` into the shared query's options, where it outlived the
      // call: an observer's `retry: times(3)` query refetched with a single
      // attempt after one `client.query` (fifth review, 2026-09-09).
      final retryConfigured = options.retry ?? defaults.retry;
      final fetch = query.fetch(
        options: retryConfigured == null
            ? _defaultQueryOptionsWith<TQueryData>(
                options.copyWith(retry: query.options.retry),
                options.queryKey,
                defaults,
              )
            : defaulted,
        fetchOptions: FetchOptions(
          retry: retryConfigured == null ? RetryPolicy.never : null,
        ),
      );
      if (returnCached) {
        fetch.ignore();
        return Future<TQueryData>.value(cachedData as TQueryData);
      }
      return fetch;
    }
    return Future<TQueryData>.value(query.state.data as TQueryData);
  }

  /// Resumes every paused mutation that can run right now, completing once
  /// they have all settled.
  ///
  /// The gate is per mutation, not global: a mutation under
  /// [NetworkMode.online] is skipped while the device is offline — resuming
  /// it would only park it on the same wait, and callers (including
  /// [mount]'s own listeners) would hang on a future that cannot complete
  /// until the network returns — while one under [NetworkMode.always] or
  /// [NetworkMode.offlineFirst] paused for focus or for its scope is resumed
  /// regardless. Upstream gates the whole call on `onlineManager.isOnline()`,
  /// so an `always` mutation paused in the background was not resumed by a
  /// refocus while offline (fifth review, 2026-09-09).
  ///
  /// [mount]'s listeners await this before the queries react, so every
  /// paused mutation — scope queues included — settles before a focus or
  /// reconnect refetch runs. The returned future completes when the resumed
  /// runs have settled: their success (or error) and settled callbacks have
  /// run and their states say so — so an `onSuccess` that writes to the cache
  /// has written before the reconnect refetch reads (ninth review,
  /// 2026-09-10, C10).
  Future<void> resumePausedMutations() => mutationCache.resumePaused();

  /// Empties both caches, cancelling in-flight fetches and every `gcTime`
  /// timer. This is the teardown call: a widget test ends with it, since
  /// Flutter's test binding asserts that no timer outlives the tree.
  /// Upstream's `clear`.
  ///
  /// Observers are not stopped: a subscribed observer — a polling one in
  /// particular — rebuilds its query on its next interaction and keeps
  /// fetching. Destroy the observers first (the Flutter binding's controllers
  /// do that in `dispose`, so a torn-down tree leaves none), then clear.
  ///
  /// A pending mutation dropped here fails — with a `CancelledError` if it
  /// was paused, with its own outcome if a request was in flight — and its
  /// error or success callbacks run a few microtasks *after* this returns.
  /// A callback that writes to the cache, an optimistic update's `onError`
  /// rollback above all, then re-creates the query it names, gc timer
  /// included: `clear()` empties the caches, it does not seal them, and a
  /// write after it is a write like any other. Upstream never runs those
  /// callbacks because it abandons a paused mutation for good; here the
  /// caller of `mutateAsync` is told. A teardown that must leave nothing
  /// pending lets the callbacks run and clears once more — the widget-test
  /// teardown the Flutter binding documents does (ninth review, 2026-09-10,
  /// C11). A mutation restored from persistence and never continued has no
  /// request of its own: it is dropped without running and without failing,
  /// as upstream drops it — and dropping a restored scope queue starts none
  /// of it, whatever the network says (MU-01, 2026-09-12).
  ///
  /// One batch for both caches, so a subscriber wrapped in
  /// `notifyManager.batchCalls` — the documented way to defer delivery —
  /// gets one scheduled flush for the call rather than one per entry
  /// removed, which is what [removeQueries] already gave it and what
  /// upstream's own `queryCache.clear()` does (pre-release review,
  /// 2026-09-12, QE-03). The batching is here rather than on
  /// [QueryCache.clear] because a cache holds no notify manager: the manager
  /// belongs to the client, and one client's batch around both caches is
  /// strictly fewer flushes than upstream's two.
  void clear() {
    notifyManager.batch(() {
      queryCache.clear();
      mutationCache.clear();
    });
  }

  // ------------------------------------------------------------ defaults

  /// The client-wide defaults in force. Upstream's `getDefaultOptions`.
  DefaultOptions getDefaultOptions() => _defaultOptions;

  /// Replaces the client-wide defaults. Takes effect on the next options
  /// resolution — an observer's next `setOptions` or a query's next fetch —
  /// not retroactively. Upstream's `setDefaultOptions`.
  void setDefaultOptions(DefaultOptions options) => _defaultOptions = options;

  /// Defaults for every query whose key starts with [queryKey].
  void setQueryDefaults(QueryKey queryKey, QueryDefaults defaults) =>
      _queryDefaults[queryKey] = defaults;

  /// The registered defaults matching [queryKey], merged in registration
  /// order.
  ///
  /// Several prefixes matching one key is the intended usage, not a mistake:
  /// register `['todos']` and then `['todos', 'detail']` and a detail query
  /// gets both, the later registration winning per field.
  QueryDefaults? getQueryDefaults(QueryKey queryKey) {
    QueryDefaults? merged;
    for (final entry in _queryDefaults.entries) {
      if (queryKey.matches(entry.key)) {
        merged = merged == null ? entry.value : merged.mergedWith(entry.value);
      }
    }
    return merged;
  }

  /// Defaults for every mutation whose key starts with [mutationKey]; the
  /// mutation twin of [setQueryDefaults]. A second registration under the
  /// same key replaces the first.
  void setMutationDefaults(QueryKey mutationKey, MutationDefaults defaults) =>
      _mutationDefaults[mutationKey] = defaults;

  /// The registered defaults matching [mutationKey], merged in registration
  /// order, later registrations winning per field — or `null` when none
  /// match. The mutation twin of [getQueryDefaults].
  MutationDefaults? getMutationDefaults(QueryKey mutationKey) {
    MutationDefaults? merged;
    for (final entry in _mutationDefaults.entries) {
      if (mutationKey.matches(entry.key)) {
        merged = merged == null ? entry.value : merged.mergedWith(entry.value);
      }
    }
    return merged;
  }

  /// The client-wide defaults merged with every registered default matching
  /// [queryKey] — one scan, whichever caller asks.
  QueryDefaults _queryDefaultsFor(QueryKey queryKey) =>
      (_defaultOptions.queries ?? const QueryDefaults())
          .mergedWith(getQueryDefaults(queryKey));

  /// Resolves [options] against the client and key defaults.
  DefaultedQueryOptions<TQueryData> defaultQueryOptions<TQueryData>(
    QueryOptions<TQueryData> options,
  ) =>
      _defaultQueryOptionsWith<TQueryData>(
        options,
        options.queryKey,
        _queryDefaultsFor(options.queryKey),
      );

  DefaultedQueryOptions<TQueryData> _defaultQueryOptionsWith<TQueryData>(
    QueryOptions<TQueryData> options,
    QueryKey queryKey,
    QueryDefaults defaults,
  ) {
    if (options.initialDataUpdatedAt != null &&
        options.initialDataUpdatedAtCompute != null) {
      throw ArgumentError(
          'Specify initialDataUpdatedAt or initialDataUpdatedAtCompute, not both.');
    }
    return DefaultedQueryOptions<TQueryData>(
      queryKey: queryKey,
      queryFn: options.queryFn ?? _adoptQueryFn<TQueryData>(defaults),
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
      initialDataUpdatedAtCompute: options.initialDataUpdatedAtCompute,
      structuralSharing: options.structuralSharing ??
          _adoptStructuralSharing<TQueryData>(defaults),
      meta: options.meta ?? defaults.meta,
      behavior: options.behavior,
    );
  }

  // The adapted wrappers, one per (erased default, data type). A wrapper
  // built per call is a new closure per call, and defaulted options compare
  // functions by identity — so a `setQueryDefaults(key, {queryFn})` made
  // every `setOptions` an options change and every rebuild an
  // `observerOptionsUpdated` (fourth review, 2026-09-09). Keyed on the
  // erased function itself, the memo lives exactly as long as the default
  // does; the wrappers close over nothing else, so they are shared across
  // clients and keys.
  //
  // One memo per adapted default. A single memo keyed on (function, data
  // type) served the query wrapper and the mutation wrapper of one function
  // from the same slot, and the same function registered as both defaults
  // handed the mutation side a `(QueryFunctionContext) => …` — a `_TypeError`
  // in the `MutationObserver` constructor (ninth review, 2026-09-10, C7).
  static final Expando<Map<Type, Function>> _adaptedQueryFns =
      Expando<Map<Type, Function>>('adapted default queryFn');
  static final Expando<Map<Type, Function>> _adaptedMutationFns =
      Expando<Map<Type, Function>>('adapted default mutationFn');
  static final Expando<Map<Type, Function>> _adaptedSharing =
      Expando<Map<Type, Function>>('adapted default structuralSharing');

  static TWrapper _memoised<TWrapper extends Function>(
    Expando<Map<Type, Function>> memo,
    Function erased,
    Type dataType,
    TWrapper Function() build,
  ) {
    final byType = memo[erased] ??= <Type, Function>{};
    final existing = byType[dataType];
    if (existing != null) {
      return existing as TWrapper;
    }
    final wrapper = build();
    byType[dataType] = wrapper;
    return wrapper;
  }

  /// Wraps an erased default [QueryDefaults.queryFn] as a typed one. A plain
  /// cast cannot work — `FutureOr<Object?> Function(…)` is not a subtype of
  /// `FutureOr<TQueryData> Function(…)` — so the value is checked on the way
  /// out, and a synchronous default stays synchronous.
  QueryFn<TQueryData>? _adoptQueryFn<TQueryData>(QueryDefaults defaults) {
    final queryFn = defaults.queryFn;
    if (queryFn == null) {
      return null;
    }
    return _memoised<QueryFn<TQueryData>>(_adaptedQueryFns, queryFn, TQueryData,
        () {
      return (context) {
        final result = queryFn(context);
        return result is Future<Object?>
            ? result
                .then((value) => _asData<TQueryData>(value, context.queryKey))
            : _asData<TQueryData>(result, context.queryKey);
      };
    });
  }

  StructuralSharing<TQueryData>? _adoptStructuralSharing<TQueryData>(
    QueryDefaults defaults,
  ) {
    final sharing = defaults.structuralSharing;
    if (sharing == null) {
      return null;
    }
    // The opt-out has to arrive as itself, not wrapped: the observer
    // recognises `noStructuralSharing()` by identity, and a wrapper closure
    // left a default-level opt-out sharing the selection anyway (pre-release
    // review, 2026-09-12, F4).
    if (isNoStructuralSharing(sharing)) {
      return noStructuralSharing<TQueryData>();
    }
    return _memoised<StructuralSharing<TQueryData>>(
        _adaptedSharing, sharing, TQueryData, () {
      return (previous, next) => _asData<TQueryData>(sharing(previous, next));
    });
  }

  /// The mutation twin of [_adoptQueryFn]. The wrapper takes `Object?`, which
  /// every `TVariables` narrows, so one wrapper per result type serves every
  /// variables type.
  MutationFn<TData, TVariables>? _adoptMutationFn<TData, TVariables>(
    MutationDefaults defaults,
  ) {
    final mutationFn = defaults.mutationFn;
    if (mutationFn == null) {
      return null;
    }
    return _memoised<MutationFn<TData, Object?>>(
        _adaptedMutationFns, mutationFn, TData, () {
      return (variables) {
        final result = mutationFn(variables);
        return result is Future<Object?>
            ? result.then((value) => _asData<TData>(value))
            : _asData<TData>(result);
      };
    });
  }

  static TQueryData _asData<TQueryData>(Object? value, [QueryKey? queryKey]) {
    if (value is TQueryData) {
      return value;
    }
    throw QueryDataTypeError(queryKey, TQueryData, value.runtimeType);
  }

  /// Resolves observer options against the client and key defaults.
  DefaultedQueryObserverOptions<TQueryData, TData>
      defaultQueryObserverOptions<TQueryData, TData>(
    QueryObserverOptionsBase<TQueryData, TData> options,
  ) {
    final queryKey = options.queryKey;
    // Resolved once: the scan over the registered defaults, with its deep key
    // matching, runs on every build.
    final queryDefaults = _queryDefaultsFor(queryKey);
    final base =
        _defaultQueryOptionsWith<TQueryData>(options, queryKey, queryDefaults);

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
      initialDataUpdatedAtCompute: base.initialDataUpdatedAtCompute,
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
      // Upstream's one dependent default: a query whose function runs
      // regardless of the network has nothing to gain from a reconnect.
      refetchOnReconnect: options.refetchOnReconnect ??
          queryDefaults.refetchOnReconnect ??
          (base.networkMode == NetworkMode.always
              ? RefetchOn.never
              : RefetchOn.ifStale),
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
      mutationFn:
          options.mutationFn ?? _adoptMutationFn<TData, TVariables>(defaults),
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

  /// Resolves infinite-query options into the observer options a
  /// `Query<InfiniteData<…>>` runs on. The paging behaviour is the options'
  /// own ([InfiniteQueryOptions.behavior]); this only adds the observer half.
  ///
  /// Public because it is the only legal input to
  /// `InfiniteQueryObserver.setOptions` and `InfiniteQueryController.setOptions`
  /// — plain observer options are refused there — and a documented path that
  /// nothing outside the package may take is not a path (seventh review,
  /// 2026-09-10). [InfiniteQueryObserver.setInfiniteOptions] is the shorter
  /// way to the same thing.
  QueryObserverOptionsBase<InfiniteData<TPageData, TPageParam>, TData>
      infiniteObserverOptions<TPageData, TPageParam, TData>(
    InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options,
  ) =>
          // The shape is kept: plain stays `QueryObserverOptions`, select stays
          // `QuerySelectOptions`, each built by the options themselves so no
          // cast is needed to say that a plain shape's TData is its
          // InfiniteData.
          options.toObserverOptions();

  /// Fetches and caches an infinite query, completing with its pages.
  ///
  /// The infinite twin of [query]: same rules (no retries unless asked for,
  /// cached data returned when it is still fresh), and the same replacement
  /// for `prefetchInfiniteQuery` and `ensureInfiniteQueryData` — `.ignore()`
  /// and `staleTime: StaleTime.static`
  /// (https://github.com/KoTTi97/flutter_query/issues/17).
  ///
  /// A typed convenience: an [InfiniteQueryOptions] carries its paging
  /// behaviour, so [query] itself pages when handed one.
  /// [revalidateIfStale] returns cached pages while stale data refreshes.
  Future<InfiniteData<TPageData, TPageParam>>
      infiniteQuery<TPageData, TPageParam>(
    InfiniteQueryOptions<TPageData, TPageParam> options, {
    bool revalidateIfStale = false,
  }) =>
          query<InfiniteData<TPageData, TPageParam>>(options,
              revalidateIfStale: revalidateIfStale);

  /// A one-off observer for [options]. The caller owns its lifetime.
  QueryObserver<TQueryData, TData> observe<TQueryData, TData>(
    QueryObserverOptionsBase<TQueryData, TData> options,
  ) =>
      QueryObserver<TQueryData, TData>(this, options);

  /// A one-off infinite observer for [options] — the twin of [observe], as
  /// [infiniteQuery] is of [query]. The caller owns its lifetime.
  InfiniteQueryObserver<TPageData, TPageParam, TData>
      observeInfinite<TPageData, TPageParam, TData>(
    InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options,
  ) =>
          InfiniteQueryObserver<TPageData, TPageParam, TData>(this, options);
}
