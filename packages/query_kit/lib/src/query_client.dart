/// The client: [QueryClient] and its defaults.
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

/// Query options that apply to many queries at once: client-wide through
/// [DefaultOptions.queries], or per key prefix through
/// [QueryClient.setQueryDefaults].
///
/// Every field is optional. When a query's options are resolved, each field
/// the query's own options leave `null` is taken from the matching key
/// defaults, then from the client-wide defaults, then from the built-in
/// default named on each field below.
///
/// Defaults serve every data type under them, and Dart cannot express
/// "options for any data type", so they carry the options that do not
/// mention the data type, plus two that are worth erasing the type for:
/// [queryFn] (a shared fetcher per key prefix is the single most useful
/// default there is) and [structuralSharing]. The rest (`initialData`,
/// `select`, `placeholderData`) belongs to a single query and is passed at
/// the call site.
///
/// ```dart
/// final client = QueryClient(
///   defaultOptions: const DefaultOptions(
///     queries: QueryDefaults(
///       staleTime: StaleTime.duration(Duration(seconds: 30)),
///       refetchOnWindowFocus: RefetchOn.never,
///     ),
///   ),
/// );
/// client.setQueryDefaults(
///   QueryKey(['reports']),
///   const QueryDefaults(gcTime: GcTime.never),
/// );
/// ```
///
/// {@category Client}
@immutable
class QueryDefaults {
  /// Creates a set of defaults; every field is optional, and an unset one
  /// defers to the next layer down (the client-wide defaults, then the
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

  /// A fetcher for every query this default covers, used when a query's own
  /// options set no `queryFn`. No built-in default.
  ///
  /// Erased to `Object?`, because one default serves every data type under a
  /// key prefix; `QueryClient.defaultQueryOptions` adapts it to the call site
  /// and throws [QueryDataTypeError] if it hands back the wrong type — the
  /// same rule the cache's typed reads follow.
  final QueryFn<Object?>? queryFn;

  /// Default for `structuralSharing`: how new data is reconciled with the
  /// data already cached. Unset, `replaceEqualDeep` is used.
  ///
  /// Erased to `Object?` for the same reason as [queryFn].
  /// `noStructuralSharing()` is recognised here too, and reaches each query
  /// as its own typed opt-out — `select` output included.
  final Object? Function(Object? previous, Object? next)? structuralSharing;

  /// Default for `enabled`: whether queries under this default fetch on their
  /// own. Built-in: [Enabled.yes].
  final Enabled? enabled;

  /// Default for `staleTime`: how long fetched data counts as fresh.
  /// Built-in: [StaleTime.zero].
  final StaleTime? staleTime;

  /// Default for `gcTime`: how long an unobserved query stays in the cache.
  /// Built-in: [GcTime.defaultValue], five minutes.
  final GcTime? gcTime;

  /// Default for `retry`: whether and how often a failed fetch is retried.
  /// Built-in: `RetryPolicy.times(3)` — except for [QueryClient.query],
  /// which does not retry unless a retry is configured somewhere.
  final RetryPolicy? retry;

  /// Default for `retryDelay`: the backoff between retries. Built-in:
  /// [RetryDelay.defaultValue], 1 s doubling up to 30 s.
  final RetryDelay? retryDelay;

  /// Default for `retryOnMount`: whether a query in error state is retried
  /// when a new observer subscribes. `true` when unset here too.
  final bool? retryOnMount;

  /// Default for `networkMode`: when a fetch may run relative to the online
  /// state. Built-in: [NetworkMode.online].
  final NetworkMode? networkMode;

  /// Default for `refetchOnMount`: whether a subscribing observer refetches
  /// data it already has. Built-in: [RefetchOn.ifStale].
  final RefetchOn? refetchOnMount;

  /// Default for `refetchOnWindowFocus`: whether the app returning to the
  /// foreground refetches. Built-in: [RefetchOn.ifStale].
  final RefetchOn? refetchOnWindowFocus;

  /// Default for `refetchOnReconnect`: whether the device coming back online
  /// refetches. Built-in: [RefetchOn.ifStale], or [RefetchOn.never] for a
  /// query under [NetworkMode.always].
  final RefetchOn? refetchOnReconnect;

  /// Default for `refetchInterval`: how often to poll, if at all. Built-in:
  /// [RefetchInterval.off].
  final RefetchInterval? refetchInterval;

  /// Default for `refetchIntervalInBackground`: whether polling continues while
  /// the app is not in the foreground. Built-in: `false`.
  final bool? refetchIntervalInBackground;

  /// Default for `meta`: opaque data handed to the query function's context and
  /// readable off the query. No built-in default.
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

/// Mutation options that apply to many mutations at once: client-wide
/// through [DefaultOptions.mutations], or per mutation-key prefix through
/// [QueryClient.setMutationDefaults].
///
/// Every field is optional; a mutation's own options win field by field,
/// then key defaults, then client-wide defaults, then the built-in default
/// named on each field. Callbacks (`onMutate`, `onSuccess`, …) have no
/// default here: they belong to a mutation's own options, or to the
/// [MutationCache] for app-wide handling.
///
/// ```dart
/// client.setMutationDefaults(
///   QueryKey(['addTask']),
///   MutationDefaults(
///     mutationFn: (variables) => api.addTask(variables! as String),
///     retry: const RetryPolicy.times(2),
///   ),
/// );
/// ```
///
/// {@category Client}
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

  /// A default mutation function for every mutation under this key, used
  /// when a mutation's own options set none. No built-in default.
  ///
  /// Erased for the same reason as [QueryDefaults.queryFn]: one default serves
  /// every variable and result type under a key prefix. Its result is
  /// checked against the mutation's data type when it arrives.
  final MutationFn<Object?, Object?>? mutationFn;

  /// Default for `retry`: whether and how often a failed mutation is retried.
  /// Built-in: [RetryPolicy.never] — mutations are not retried unless asked.
  final RetryPolicy? retry;

  /// Default for `retryDelay`: the backoff between retries. Built-in:
  /// [RetryDelay.defaultValue].
  final RetryDelay? retryDelay;

  /// Default for `networkMode`: when a mutation may run relative to the online
  /// state. Built-in: [NetworkMode.online].
  final NetworkMode? networkMode;

  /// Default for `gcTime`: how long a settled, unobserved mutation stays in
  /// the cache. Built-in: [GcTime.defaultValue], five minutes.
  final GcTime? gcTime;

  /// Default for `scope`: mutations sharing a scope run one at a time, in
  /// submission order. No built-in default: unscoped mutations run in
  /// parallel.
  final MutationScope? scope;

  /// Default for `meta`: opaque data readable off the mutation. No built-in
  /// default.
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

/// Client-wide defaults, passed to the [QueryClient] constructor or to
/// [QueryClient.setDefaultOptions].
///
/// They sit beneath key-specific defaults ([QueryClient.setQueryDefaults],
/// [QueryClient.setMutationDefaults]) and beneath each query's or
/// mutation's own options: a field set closer to the call wins.
///
/// ```dart
/// final client = QueryClient(
///   defaultOptions: const DefaultOptions(
///     queries: QueryDefaults(retry: RetryPolicy.times(1)),
///     mutations: MutationDefaults(networkMode: NetworkMode.always),
///   ),
/// );
/// ```
///
/// {@category Client}
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

/// The entry point of query_kit: owns the caches and everything imperative —
/// fetching, reading and writing cached data, invalidating, cancelling.
///
/// A client holds a [QueryCache] (every query, keyed by [QueryKey]) and a
/// [MutationCache], the client-wide and per-key defaults, and three
/// managers: [focusManager] and [onlineManager], which tell it when the app
/// returns to the foreground or the network comes back, and
/// [notifyManager], which batches listener notifications.
///
/// **Lifetime.** Create one client per app (or per test) and keep it for as
/// long as the app runs — the cache lives in it, so a second client is a
/// second, empty cache. Call [mount] once so it reacts to focus and
/// connectivity (the Flutter binding's `QueryClientProvider` does this for
/// you), and [unmount] and [clear] when you are done: a client owns
/// `gcTime` timers that would otherwise keep a process or a test alive.
///
/// The most used members, grouped:
///
/// * **Fetch:** [query], [infiniteQuery] — fetch and cache, completing with
///   the data (TanStack Query's `fetchQuery`/`prefetchQuery`/
///   `ensureQueryData` in one method).
/// * **Observe:** [observe], [observeInfinite] — create a [QueryObserver]
///   that follows a query and refetches it on the triggers its options name.
/// * **Read:** [getQueryData], [getQueryState], [getQueriesData],
///   [isFetching], [isMutating].
/// * **Write:** [setQueryData], [updateQueryData], [updateQueriesData] — the
///   tools for optimistic updates and for seeding the cache.
/// * **Operate on many queries** (by [QueryFilters]): [invalidateQueries],
///   [refetchQueries], [cancelQueries], [resetQueries], [removeQueries].
/// * **Defaults:** [setDefaultOptions], [setQueryDefaults],
///   [setMutationDefaults].
/// * **Lifecycle:** [mount], [unmount], [clear], [resumePausedMutations].
///
/// ```dart
/// final client = QueryClient()..mount();
/// final todosKey = QueryKey(['todos']);
///
/// // Fetch once and cache; a second call within staleTime is served from
/// // the cache.
/// final todos = await client.query(QueryOptions<List<String>>(
///   queryKey: todosKey,
///   queryFn: (context) => api.fetchTodos(),
///   staleTime: const StaleTime.duration(Duration(minutes: 1)),
/// ));
///
/// // Write to the cache, e.g. after a mutation or optimistically.
/// client.setQueryData<List<String>>(todosKey, [...todos, 'Buy milk']);
///
/// // Mark stale and refetch everything under the key that is observed.
/// await client.invalidateQueries(filters: QueryFilters(queryKey: todosKey));
///
/// // When done (end of a test, a CLI's exit):
/// client.unmount();
/// client.clear();
/// ```
///
/// {@category Client}
class QueryClient {
  /// Creates a client. Every collaborator is optional: a fresh [QueryCache],
  /// [MutationCache], [AppFocusManager], [OnlineManager] and [NotifyManager]
  /// are made when none is passed, and [defaultOptions] starts empty. Pass
  /// your own caches to install cache-wide callbacks (for example a global
  /// `onError`). Call [mount] to have it react to focus and connectivity,
  /// and [clear] when it is done — a client owns `gcTime` timers that
  /// outlive any widget tree.
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

  /// Whether the app is in the foreground. A [mount]ed client refetches
  /// stale queries (per `refetchOnWindowFocus`) when it reports focus
  /// again. The Flutter binding drives it from the app lifecycle.
  ///
  /// Owned by the client rather than global (unlike TanStack Query's
  /// module-level singleton), so tests are hermetic.
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
  /// overtake the mutation it was meant to reflect, as in TanStack Query.
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
  ///
  /// [then] runs in one [NotifyManager.batch], as TanStack Query's
  /// `QueryCache.onFocus` and `onOnline` batch themselves: a resume that
  /// refetches N queries is one flush for a deferred subscriber, not N.
  Future<void> _resumeThen(void Function() then) async {
    try {
      await resumePausedMutations();
      notifyManager.batch(then);
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  /// Stops listening for focus and connectivity changes.
  ///
  /// Mounts are counted: [mount] twice and the client stops listening only
  /// after the second [unmount]. An unmount without a matching mount does
  /// nothing. Unmounting does not touch the caches — call [clear] for that.
  void unmount() {
    if (_mountCount == 0) {
      // Never below zero. An unmount without a matching mount used to leave
      // the count at -1, and the next `mount()` then took it to 0 and
      // subscribed to nothing: focus and reconnect refetching off for the
      // life of the client, silently.
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
  /// fetching, not paused. Every query when the filters are empty.
  ///
  /// The count always looks at `fetching` queries: a
  /// [QueryFilters.fetchStatus] passed here is ignored rather than combined,
  /// so it cannot make the count 0 (as with TanStack Query's `isFetching`).
  ///
  /// ```dart
  /// final busy = client.isFetching(
  ///   filters: QueryFilters(queryKey: QueryKey(['todos'])),
  /// );
  /// ```
  int isFetching({QueryFilters filters = const QueryFilters()}) => queryCache
      .findAll(
        filters: QueryFilters(
          queryKey: filters.queryKey,
          exact: filters.exact,
          type: filters.type,
          stale: filters.stale,
          fetchStatus: FetchStatus.fetching,
          status: filters.status,
          predicate: filters.predicate,
        ),
      )
      .length;

  /// How many mutations matching [filters] are pending right now. Every
  /// mutation when the filters are empty. The count always looks at
  /// `pending` mutations: a [MutationFilters.status] passed here is ignored
  /// rather than combined.
  ///
  /// A mutation counts until its run has finished, callbacks included: it is
  /// `pending` while the cache's and its options' `onSuccess`/`onError` and
  /// `onSettled` run, and until the future `onSettled` returned has
  /// completed. So `onSettled` sees itself in this count —
  /// `isMutating(...) > 1` there means another matching mutation is pending
  /// — as in TanStack Query. The per-call callbacks passed to `mutate` run
  /// after the state has moved on.
  int isMutating({MutationFilters filters = const MutationFilters()}) =>
      mutationCache
          .findAll(
            filters: MutationFilters(
              mutationKey: filters.mutationKey,
              exact: filters.exact,
              status: MutationStatus.pending,
              predicate: filters.predicate,
            ),
          )
          .length;

  /// The cached data under [queryKey], or `null` if there is none.
  ///
  /// A plain read: it neither fetches nor subscribes, and it returns stale
  /// data as readily as fresh. Name the type the entry holds:
  /// `client.getQueryData<List<Todo>>(key)`. Throws [QueryDataTypeError] if
  /// the entry holds a different type.
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
  QueryState<TQueryData>? getQueryState<TQueryData>(QueryKey queryKey) =>
      queryCache.get<TQueryData>(queryKey)?.state;

  /// The cached data of every matching query, `null` where a query holds
  /// none yet.
  ///
  /// Throws [QueryDataTypeError] if a matching query holds another type, as
  /// [getQueryData] does — a `null` there would read as "nothing cached" and
  /// hide the bug.
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
  /// Every observer of the key sees the new data at once, and the entry
  /// counts as freshly fetched ([updatedAt], default now) — the tool for
  /// optimistic updates and for putting a mutation's response into the
  /// cache without a refetch:
  ///
  /// ```dart
  /// client.setQueryData<Todo>(QueryKey(['todos', todo.id]), todo);
  /// ```
  ///
  /// The type argument is inferred from [data], and a value infers
  /// narrowly: `setQueryData(key, 'x')` is a `String` write. An entry that
  /// already exists takes any value its own type can hold, so that write
  /// lands in a query holding `String?`, and a sealed type's variant lands in
  /// a query of the sealed type. A value the entry cannot hold throws
  /// [QueryDataTypeError]. The type argument still decides the type of an
  /// entry this call *creates* — name it when seeding a key before its query
  /// exists: `setQueryData<List<Todo>>(key, [])`.
  ///
  /// Returns what the cache now holds: after structural sharing, that is the
  /// instance already cached when [data] is deep-equal to it.
  ///
  /// A bare `setQueryData(key, null)` — the type argument inferred as `Null`
  /// — writes nothing and returns `null`, as TanStack Query's
  /// `setQueryData(key, undefined)` does. To store `null`, name the entry's
  /// nullable type: `setQueryData<Todo?>(key, null)`.
  TQueryData setQueryData<TQueryData>(
    QueryKey queryKey,
    TQueryData data, {
    DateTime? updatedAt,
  }) {
    // A bare `setQueryData(key, null)` infers `Null`: upstream's
    // `setQueryData(key, undefined)`, which writes nothing. Written, it
    // nulled the data of an existing entry, or created a `Query<Null>` that
    // made every typed reader of the key throw until it was collected. A
    // deliberate null write names the entry's type:
    // `setQueryData<Todo?>(key, null)`.
    if (TQueryData == Null) {
      return data;
    }
    final existing = queryCache.peek(queryKey);
    if (existing != null &&
        existing.dataType != TQueryData &&
        _holds<TQueryData>(existing, data)) {
      // What sharing stored, as the typed path and upstream return it; the
      // argument only when the stored value is not a `TQueryData` — an older
      // instance of a wider type kept by sharing.
      final stored = existing.setData(data, updatedAt: updatedAt, manual: true);
      return stored is TQueryData ? stored : data;
    }
    final query = queryCache.build<TQueryData>(
      this,
      defaultQueryOptions<TQueryData>(
        QueryOptions<TQueryData>(queryKey: queryKey),
      ),
    );
    return query.setData(data, updatedAt: updatedAt, manual: true);
  }

  /// Whether [query] takes [data] through [setQueryData]: a value of its own
  /// type — exactly, or one its type can hold.
  ///
  /// Not for paged data: an `InfiniteData` inferred from its literals is
  /// narrower in its type arguments, not in its value, and once stored the
  /// next `copyWith` typed for the entry fails its covariant parameter check
  /// with a raw `TypeError`, far from this write. It keeps the loud error.
  static bool _holds<TQueryData>(Query<Object?> query, TQueryData data) =>
      query.dataType == TQueryData ||
      (data is! InfiniteData<Object?, Object?> && query.canHold(data));

  /// What [query] holds, for an updater typed
  /// `TQueryData? Function(TQueryData?)` — or [QueryDataTypeError] when the
  /// held data is not a `TQueryData`.
  static TQueryData? _heldFor<TQueryData>(Query<Object?> query) {
    final held = query.state.hasData ? query.state.data : null;
    if (held is! TQueryData?) {
      throw QueryDataTypeError(query.queryKey, TQueryData, query.dataType);
    }
    return held;
  }

  /// Updates the cached data under [queryKey] from what it holds now.
  ///
  /// [updater] receives the current data (`null` when there is none) and
  /// returns the new data; returning `null` leaves the cache untouched.
  /// Returns what the cache now holds, or `null` when nothing was written.
  ///
  /// ```dart
  /// client.updateQueryData<List<Todo>>(
  ///   QueryKey(['todos']),
  ///   (previous) => [...?previous, newTodo],
  /// );
  /// ```
  ///
  /// TanStack Query folds this into `setQueryData`; it is a method of its own
  /// here because Dart cannot overload on "a value or a function".
  ///
  /// Takes what [setQueryData] takes. `TQueryData` usually infers from the
  /// updater's parameter, so `(Todo? old) => …` is a `Todo` update, and it
  /// lands in an entry holding `Todo?` or a supertype of `Todo`. What the
  /// entry holds must be a `TQueryData` for the updater to see it, and what
  /// the updater returns must be a value the entry can hold; either failing
  /// throws [QueryDataTypeError].
  TQueryData? updateQueryData<TQueryData>(
    QueryKey queryKey,
    TQueryData? Function(TQueryData? previous) updater, {
    DateTime? updatedAt,
  }) {
    final existing = queryCache.peek(queryKey);
    final previous = existing == null ? null : _heldFor<TQueryData>(existing);
    final next = updater(previous);
    if (next == null) {
      return null;
    }
    return setQueryData<TQueryData>(queryKey, next, updatedAt: updatedAt);
  }

  /// Runs [updater] over every query matching [filters] and returns each key
  /// with what it now holds. A type mismatch anywhere under the filters
  /// throws before anything is written. The filtered twin of
  /// [updateQueryData] (TanStack Query's `setQueriesData`), and as lenient:
  /// a matching entry takes any value its own type can hold.
  ///
  /// For the mismatch to be caught before the first write, every updater
  /// runs before any value is written (TanStack Query calls each one just
  /// before its own write). An updater that reads another matched key's
  /// cache entry therefore sees it unwritten.
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
    // throws with the cache untouched rather than half-updated: what each
    // entry holds, then what each updater returned for it.
    final previous = [for (final query in queries) _heldFor<TQueryData>(query)];
    final next = [for (final held in previous) updater(held)];
    for (var i = 0; i < queries.length; i++) {
      final value = next[i];
      if (value != null && !_holds<TQueryData>(queries[i], value)) {
        throw QueryDataTypeError(
          queries[i].queryKey,
          TQueryData,
          queries[i].dataType,
        );
      }
    }
    return notifyManager.batch(
      () => [
        for (var i = 0; i < queries.length; i++)
          (
            queries[i].queryKey,
            switch (next[i]) {
              null => null,
              final TQueryData value => setQueryData<TQueryData>(
                  queries[i].queryKey,
                  value,
                  updatedAt: updatedAt,
                ),
            },
          ),
      ],
    );
  }

  // ---------------------------------------------------------- operations

  /// Cancels every matching in-flight fetch, completing once they have all
  /// settled.
  ///
  /// [revert] (default `true`) puts each query back to the state it held
  /// before the cancelled fetch. [silent] cancels without dispatching an
  /// error; it is *not* on by default, because a silent cancel means "a new
  /// fetch is taking over", which is not what an explicit cancel is. A
  /// silently cancelled fetch that nothing replaces is put back to `idle`
  /// rather than left `fetching` forever — see [Query.cancel].
  ///
  /// The usual first step of an optimistic update, so that a refetch in
  /// flight cannot overwrite the optimistic data:
  ///
  /// ```dart
  /// await client.cancelQueries(filters: QueryFilters(queryKey: todosKey));
  /// ```
  Future<void> cancelQueries({
    QueryFilters filters = const QueryFilters(),
    bool revert = true,
    bool silent = false,
  }) async {
    // Batched like the other bulk operations: every revert is dispatched
    // inside one transaction.
    final cancels = notifyManager.batch(
      () => queryCache
          .findAll(filters: filters)
          .map((query) => query.cancel(revert: revert, silent: silent))
          .toList(),
    );
    // TanStack's promise "never rejects, even if individual cancellations
    // fail". No public call could be made to fail one; the guarantee is kept
    // all the same. Each future
    // gets its own handler, attached before anything is awaited: a bare
    // `Future.wait` reports a second failure to the zone.
    await Future.wait<void>([
      for (final cancel in cancels)
        cancel.then<void>((_) {}, onError: (Object _) {}),
    ]);
  }

  /// Removes every query matching [filters] from the cache — all of them when
  /// the filters are empty — cancelling their fetches silently.
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
  /// Completes when the refetches have settled; a refetch's failure does not
  /// fail the returned future (it lands in the query's state). With [cancelRefetch]
  /// (default `true`) a fetch already in flight on a query that holds data
  /// is cancelled and started over; on a query without data it is joined.
  ///
  /// `async`, like [cancelQueries], [invalidateQueries] and
  /// [refetchQueries]: a throwing filter predicate fails the returned future
  /// rather than throwing out of the call, so those four report it the same
  /// way. [removeQueries] returns nothing, so there it throws out of the
  /// call.
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
  /// [QueryTypeFilter.active] — the queries an observer is watching. Queries
  /// nobody watches are only marked, and refetch when next observed.
  ///
  /// The usual way to say "the server data changed": after a mutation,
  /// invalidate the keys it affected.
  ///
  /// ```dart
  /// // Everything under ['todos'], lists and details alike:
  /// await client.invalidateQueries(
  ///   filters: QueryFilters(queryKey: QueryKey(['todos'])),
  /// );
  /// // Mark only; refetch nothing now:
  /// await client.invalidateQueries(refetchType: RefetchType.none);
  /// ```
  ///
  /// The returned future completes when the refetches have settled; their
  /// failures land in the queries' states, not here. With [cancelRefetch]
  /// (default `true`) a fetch already in flight on a query that holds data
  /// is restarted so the result reflects the invalidation; on a query
  /// without data it is joined. `async` for the reason [resetQueries] is.
  Future<void> invalidateQueries({
    QueryFilters filters = const QueryFilters(),
    RefetchType? refetchType,
    bool cancelRefetch = true,
  }) async =>
      notifyManager.batch(() {
        // The matched set is captured *before* invalidating, as `resetQueries`
        // does: a filter that looks at state (`stale: false`, a predicate over
        // `query.state.isInvalidated`) no longer matches once the query has
        // been marked, and re-running the same filter for the refetch (as
        // TanStack does) would refetch none of the queries just invalidated.
        // Only the `type` is re-evaluated, since
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

  /// Refetches every query matching [filters] — all of them when the filters
  /// are empty — whether stale or not.
  ///
  /// Skipped are queries that cannot fetch on their own: disabled ones
  /// ([Enabled.no], or an [Enabled.when] saying no) and ones an observer
  /// marks [StaleTime.static]. With [cancelRefetch] (default `true`) a fetch
  /// already in flight is cancelled and started again if the query holds
  /// data, and joined if it does not; `false` always joins it.
  ///
  /// The returned future completes when every refetch has settled; failures
  /// land in the queries' states and do not fail it. A fetch paused for the
  /// network is not waited for.
  ///
  /// ```dart
  /// await client.refetchQueries(
  ///   filters: const QueryFilters(type: QueryTypeFilter.active),
  /// );
  /// ```
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
  /// If the cache already holds data that is fresh under the options'
  /// `staleTime`, that data is returned without a fetch; otherwise the query
  /// is fetched (or a fetch already in flight is joined), cached, and its
  /// data returned. A failed fetch fails the returned future.
  ///
  /// The imperative counterpart of an observer: no `enabled`, no refetch
  /// triggers, and **no retries unless asked for** (set `retry` on the
  /// options or in the defaults), since there is no widget to catch a thrown
  /// error and try again — the same rule as TanStack Query's.
  ///
  /// ```dart
  /// final todos = await client.query(QueryOptions<List<Todo>>(
  ///   queryKey: QueryKey(['todos']),
  ///   queryFn: (context) => api.fetchTodos(),
  /// ));
  /// ```
  ///
  /// TanStack Query has three methods here — `fetchQuery`, `prefetchQuery`
  /// and `ensureQueryData`. This package has this one method, which covers
  /// all three:
  ///
  /// - to prefetch, ignore the future: `client.query(options).ignore()`;
  /// - to fetch only when nothing is cached, pass
  ///   `staleTime: StaleTime.static`;
  /// - to reshape the result, `await` it and map it — Dart needs no `select`
  ///   here.
  ///
  /// With [revalidateIfStale], existing data is returned immediately while a
  /// stale query refreshes in the background. Missing data still awaits the
  /// fetch. Background errors update the cache and its callbacks as usual.
  ///
  /// That last point changes when this call throws: with [revalidateIfStale]
  /// the future fails only when nothing is cached at all. A query holding
  /// stale data completes with that data even when it is in an error state and
  /// even when the background refresh fails too — the error reaches the state
  /// and the cache callbacks, not this caller.
  ///
  /// **"Fresh" means "no older than a fetch in flight", not "started after
  /// this call".** When the data is stale — always, with `staleTime:
  /// StaleTime.zero` — and the query is already fetching, this call joins
  /// that fetch, which may have started before a write the caller just made;
  /// it does not cancel and restart it. And if that fetch is then cancelled
  /// with `revert` (`cancelQueries`' default, and what an optimistic
  /// update's `onMutate` usually calls), the call completes with the
  /// reverted data — whatever the cache held before the fetch, an
  /// optimistic patch included — rather than failing. TanStack Query's
  /// `fetchQuery` behaves the same way on both counts and has no option to
  /// force a new fetch either. A caller that needs a fetch that begins after
  /// its own write can `await client.refetchQueries(...)` for the key, whose
  /// `cancelRefetch` defaults to `true`, and then read the cache.
  ///
  /// **The options become the query's options**, as an observer's do: the
  /// cache entry is shared, and it runs its later refetches — an
  /// invalidation, a focus refetch — with the options it was last handed. An
  /// explicit `retry` passed here therefore stays on the query after this
  /// call, like its `queryFn` or `gcTime`, until an observer or another call
  /// hands in its own; TanStack Query's `fetchQuery` does the same. Only the
  /// no-retry default for a caller who configured none is limited to this
  /// one fetch.
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
      // The imperative-path rule — a caller who configured nothing gets no
      // retries — applied to this fetch alone. TanStack writes `retry: 0`
      // into the shared query's options, where it outlives the call: an
      // observer's `retry: times(3)` query would refetch with a single
      // attempt after one `client.query`.
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
  /// A mounted client calls this itself on focus and reconnect; call it by
  /// hand after restoring mutations from storage, or when not mounted.
  ///
  /// The gate is per mutation, not global: a mutation under
  /// [NetworkMode.online] is skipped while the device is offline — resuming
  /// it would only park it on the same wait, and callers (including
  /// [mount]'s own listeners) would hang on a future that cannot complete
  /// until the network returns — while one under [NetworkMode.always] or
  /// [NetworkMode.offlineFirst] paused for focus or for its scope is resumed
  /// regardless. (TanStack Query gates the whole call on being online, so
  /// there an `always` mutation paused in the background is not resumed by
  /// a refocus while offline.)
  ///
  /// [mount]'s listeners await this before the queries react, so every
  /// paused mutation — scope queues included — settles before a focus or
  /// reconnect refetch runs. The returned future completes when the resumed
  /// runs have settled: their success (or error) and settled callbacks have
  /// run and their states say so — so an `onSuccess` that writes to the cache
  /// has written before the reconnect refetch reads.
  Future<void> resumePausedMutations() => mutationCache.resumePaused();

  /// Empties both caches, cancelling in-flight fetches and every `gcTime`
  /// timer. This is the teardown call: a widget test ends with it, since
  /// Flutter's test binding asserts that no timer outlives the tree.
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
  /// write after it is a write like any other. (TanStack Query never runs
  /// those callbacks because it abandons a paused mutation for good; here
  /// the caller of `mutateAsync` is told.) A teardown that must leave
  /// nothing pending lets the callbacks run and clears once more — the
  /// widget-test teardown the Flutter binding documents does. A mutation
  /// restored from persistence and never continued has no request of its
  /// own: it is dropped without running and without failing — and dropping
  /// a restored scope queue starts none of it, whatever the network says.
  ///
  /// One batch for both caches, so a subscriber wrapped in
  /// `notifyManager.batchCalls` — the documented way to defer delivery —
  /// gets one scheduled flush for the call rather than one per entry
  /// removed. The batching is here rather than on [QueryCache.clear] because
  /// a cache holds no notify manager: the manager belongs to the client.
  void clear() {
    notifyManager.batch(() {
      queryCache.clear();
      mutationCache.clear();
    });
  }

  // ------------------------------------------------------------ defaults

  /// The client-wide defaults in force.
  DefaultOptions getDefaultOptions() => _defaultOptions;

  /// Replaces the client-wide defaults. Takes effect wherever options are
  /// resolved next — a new observer, an observer's next `setOptions`, or a
  /// client call such as [query]. Options already resolved, such as those a
  /// query holds, are not changed.
  void setDefaultOptions(DefaultOptions options) => _defaultOptions = options;

  /// Defaults for every query whose key starts with [queryKey].
  ///
  /// They sit between the client-wide [DefaultOptions] and a query's own
  /// options. Registering the same key again replaces its defaults; several
  /// matching prefixes merge (see [getQueryDefaults]).
  ///
  /// ```dart
  /// client.setQueryDefaults(
  ///   QueryKey(['todos']),
  ///   QueryDefaults(
  ///     queryFn: (context) => api.get(context.queryKey.parts),
  ///     staleTime: const StaleTime.duration(Duration(minutes: 1)),
  ///   ),
  /// );
  /// ```
  void setQueryDefaults(QueryKey queryKey, QueryDefaults defaults) =>
      _queryDefaults[queryKey] = defaults;

  /// The registered defaults matching [queryKey], merged in the order the
  /// keys were first registered — registering a key again replaces its
  /// defaults but keeps its place.
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

  /// The registered defaults matching [mutationKey], merged in the order the
  /// keys were first registered, later ones winning per field — or `null`
  /// when none match. The mutation twin of [getQueryDefaults].
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

  /// Resolves [options] against the key defaults, the client-wide defaults
  /// and the built-in defaults, filling in every field left `null`.
  ///
  /// The cache and the observers call this; application code rarely needs
  /// it, except to see which options a query will actually run with.
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
  // `observerOptionsUpdated`. Keyed on the
  // erased function itself, the memo lives exactly as long as the default
  // does; the wrappers close over nothing else, so they are shared across
  // clients and keys.
  //
  // One memo per adapted default. A single memo keyed on (function, data
  // type) served the query wrapper and the mutation wrapper of one function
  // from the same slot, and the same function registered as both defaults
  // handed the mutation side a `(QueryFunctionContext) => …` — a `_TypeError`
  // in the `MutationObserver` constructor.
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
    // left a default-level opt-out sharing the selection anyway.
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

  /// Resolves observer options against the key defaults, the client-wide
  /// defaults and the built-in defaults — the query half as
  /// [defaultQueryOptions] does, plus the observer-only fields
  /// (`refetchOn*`, `refetchInterval`, `retryOnMount`, …).
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
      // The one dependent default: a query whose function runs
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

  /// Resolves mutation options against the key defaults, the client-wide
  /// defaults and the built-in defaults. Throws [ArgumentError] when both
  /// `mutationFn` and `mutationFnWithContext` are set.
  DefaultedMutationOptions<TData, TVariables, TOnMutateResult>
      defaultMutationOptions<TData, TVariables, TOnMutateResult>(
    MutationOptions<TData, TVariables, TOnMutateResult> options,
  ) {
    if (options.mutationFn != null && options.mutationFnWithContext != null) {
      // Not only an assert: two functions where one runs is wrong in a
      // release build too, and there the context one would win without a
      // word. A debug build fails earlier, at the literal — the constructor
      // asserts.
      throw ArgumentError(
          'Give a mutation one function: mutationFn or mutationFnWithContext.');
    }
    final mutationKey = options.mutationKey;
    final defaults =
        (_defaultOptions.mutations ?? const MutationDefaults()).mergedWith(
      mutationKey == null ? null : getMutationDefaults(mutationKey),
    );

    return DefaultedMutationOptions<TData, TVariables, TOnMutateResult>(
      mutationKey: mutationKey,
      mutationFn: options.mutationFnWithContext != null
          ? null
          : options.mutationFn ?? _adoptMutationFn<TData, TVariables>(defaults),
      mutationFnWithContext: options.mutationFnWithContext,
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
  /// `InfiniteQueryObserver.setOptions` and
  /// `InfiniteQueryController.setOptions` — plain observer options are
  /// refused there.
  /// [InfiniteQueryObserver.setInfiniteOptions] is the shorter way to the
  /// same thing.
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
  /// cached data returned when it is still fresh), and it covers TanStack
  /// Query's `fetchInfiniteQuery`, `prefetchInfiniteQuery` and
  /// `ensureInfiniteQueryData` the same way — `.ignore()` the future to
  /// prefetch, `staleTime: StaleTime.static` to fetch only when nothing is
  /// cached. A first fetch loads the first page, or as many as
  /// `InfiniteQueryOptions.pages` asks for.
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

  /// Creates a [QueryObserver] for [options] on this client — the same as
  /// `QueryObserver(client, options)`.
  ///
  /// The observer does nothing until subscribed; the caller owns its
  /// lifetime and must unsubscribe (or `destroy` it) when done.
  ///
  /// ```dart
  /// final observer = client.observe(QueryObserverOptions<List<Todo>>(
  ///   queryKey: QueryKey(['todos']),
  ///   queryFn: (context) => api.fetchTodos(),
  /// ));
  /// final unsubscribe = observer.subscribe((result) => print(result));
  /// // later
  /// unsubscribe();
  /// ```
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
