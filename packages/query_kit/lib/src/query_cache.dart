/// The query cache, its events, and the error for a key read as the wrong
/// type.
library;

import 'package:meta/meta.dart';

import 'filters.dart';
import 'query.dart';
import 'query_client.dart';
import 'query_key.dart';
import 'query_options.dart';
import 'query_state.dart';
import 'subscribable.dart';

/// Something happened to a query in the cache: what [QueryCache.subscribe]
/// delivers to its listeners.
///
/// Sealed, so a listener can `switch` over it exhaustively. The events are:
///
/// * [QueryAdded] — a query was created in the cache.
/// * [QueryRemoved] — a query left the cache.
/// * [QueryUpdated] — a query's state changed; carries the [QueryAction].
/// * [QueryObserverAdded] / [QueryObserverRemoved] — an observer attached to
///   or detached from a query.
/// * [QueryObserverOptionsUpdated] — an observer's options changed.
/// * [QueryObserverResultsUpdated] — an observer delivered a new result.
///
/// Events are for watching: logging, devtools, persisting the cache. To
/// react to a fetch's outcome, the [QueryCache] constructor's `onSuccess`,
/// `onError` and `onSettled` hooks are simpler.
///
/// {@category Advanced}
@immutable
sealed class QueryCacheEvent {
  /// Creates the event for [query].
  const QueryCacheEvent(this.query);

  /// The query the event is about. Typed as `Query<Object?>`, since a cache
  /// listener sees every key; read `dataType` or `get<T>` it from the cache to
  /// recover the concrete type.
  final Query<Object?> query;
}

/// A query was created and put into the cache, by [QueryCache.build] or
/// [QueryCache.add] — the first time anything used its key. TanStack Query
/// calls this event `added`.
///
/// {@category Advanced}
final class QueryAdded extends QueryCacheEvent {
  /// Creates the event for [query].
  const QueryAdded(super.query);
}

/// A query left the cache: it was garbage-collected after its `gcTime`
/// without observers, or removed through `QueryClient.removeQueries`,
/// [QueryCache.remove] or [QueryCache.clear]. TanStack Query calls this
/// event `removed`.
///
/// {@category Advanced}
final class QueryRemoved extends QueryCacheEvent {
  /// Creates the event for [query].
  const QueryRemoved(super.query);
}

/// A query's state changed. Emitted for every [QueryAction] — fetch,
/// success, error, invalidate, pause, and the rest — so this is the event a
/// devtools panel or a persister keys its work off. TanStack Query calls
/// this event `updated`.
///
/// {@category Advanced}
final class QueryUpdated extends QueryCacheEvent {
  /// Creates the event for [query], carrying the [action] that changed it.
  const QueryUpdated(super.query, this.action);

  /// The transition that produced the query's new state. Sealed, so a listener
  /// can `switch` over it exhaustively.
  final QueryAction action;
}

/// An observer subscribed to the query. Emitted the moment the observer
/// attaches, which is also what cancels the query's pending garbage
/// collection. TanStack Query calls this event `observerAdded`.
///
/// {@category Advanced}
final class QueryObserverAdded extends QueryCacheEvent {
  /// Creates the event for [query] and the [observer] that attached.
  const QueryObserverAdded(super.query, this.observer);

  /// The observer that attached. Read-only from outside: it is an identity to
  /// hold and compare, not something to drive.
  final QueryObserverRef observer;
}

/// An observer unsubscribed from the query. Emitted after the observer has
/// been detached — and, when it was the last one, after the fetch in flight
/// has been told to stop retrying and the garbage-collection timer has been
/// started. TanStack Query calls this event `observerRemoved`.
///
/// {@category Advanced}
final class QueryObserverRemoved extends QueryCacheEvent {
  /// Creates the event for [query] and the [observer] that detached.
  const QueryObserverRemoved(super.query, this.observer);

  /// The observer that detached. Read-only from outside.
  final QueryObserverRef observer;
}

/// An observer's options were replaced — a rebuild that changed `staleTime`,
/// `enabled` or a callback, say. Emitted for every change of options, a key
/// change included: moving an observer to a different key emits
/// [QueryObserverRemoved] on the old query and [QueryObserverAdded] on the
/// new one, and then this event on the new query. TanStack Query calls this
/// event `observerOptionsUpdated` and orders it the same way.
///
/// {@category Advanced}
final class QueryObserverOptionsUpdated extends QueryCacheEvent {
  /// Creates the event for [query] and the [observer] whose options changed.
  const QueryObserverOptionsUpdated(super.query, this.observer);

  /// The observer whose options changed. Read-only from outside.
  final QueryObserverRef observer;
}

/// An observer of the query delivered a new result to its listeners. Emitted
/// once per delivery, after the listeners have run, so a devtools panel can
/// mirror what the UI just saw. TanStack Query calls this event
/// `observerResultsUpdated`.
///
/// {@category Advanced}
final class QueryObserverResultsUpdated extends QueryCacheEvent {
  /// Creates the event for [query].
  const QueryObserverResultsUpdated(super.query);
}

/// Thrown when a query is read as one data type but holds another — or when
/// an erased default (`QueryDefaults.queryFn`, `structuralSharing`,
/// `MutationDefaults.mutationFn`) hands back a value of the wrong type.
///
/// Each key holds exactly one data type. Reading or writing it as another
/// type is always a bug in the calling code, so it fails loudly here rather
/// than returning a silent `null` or a wrongly typed value (TanStack Query
/// casts without checking). It is thrown
/// *synchronously*, from the call that reads or writes the key —
/// `getQueryData`, `setQueryData`, `getQueriesData`, `updateQueriesData`,
/// `QueryClient.query` and an observer's `setOptions` all throw before any
/// future exists; only the erased-default case surfaces through the fetch or
/// mutation the default ran in, as its error. [queryKey] is `null` when the
/// default that produced the value has no key to name: a sharing hook sees
/// only the data, and a mutation function only its variables.
///
/// A common cause is an inferred type argument: `setQueryData` or
/// `getQueryData` called without `<T>` on a query whose type is nullable or
/// wider than the value. The message then says which type argument to name.
///
/// {@category Errors}
final class QueryDataTypeError implements Exception {
  /// Creates the error for a use of [queryKey] — a read or a write — that
  /// [expected] one type and found [actual].
  const QueryDataTypeError(this.queryKey, this.expected, this.actual);

  /// The key that was read or written, or `null` when the mismatch came from
  /// a keyless default such as a `structuralSharing` hook.
  final QueryKey? queryKey;

  /// The data type the caller asked for — read as, or written with.
  final Type expected;

  /// The data type the query (or the default's value) actually holds.
  final Type actual;

  @override
  String toString() {
    final key = queryKey;
    if (key == null) {
      return 'A default produced $actual where $expected was expected. One '
          'default is being used with two data types.';
    }
    // A read or write typed `String` against a `Query<String?>`: the type
    // argument inferred the non-nullable type, and naming the query's type
    // is the cure. Which call it was is not known here, so the cure names
    // the type, not a method.
    final cure = '$actual' == '$expected?'
        ? " The query's type is nullable and the type argument inferred the "
            'non-nullable one: name the type argument <$actual> on the call.'
        : '';
    return 'Query $key holds $actual but was used as $expected. One key is '
        'being used with two data types.$cure';
  }
}

/// Every query of one [QueryClient], stored under its [QueryKey].
///
/// A client owns exactly one query cache, and usually creates it itself:
/// `QueryClient()` makes an empty one. Queries are added as observers and
/// fetches first use a key, and leave again when they are garbage-collected
/// (after `gcTime` without observers) or removed. Most code never touches the
/// cache directly — the client's methods (`getQueryData`,
/// `invalidateQueries`, ...) work through it.
///
/// Reasons to reach for it:
///
/// * **Cache-wide hooks.** Pass [onSuccess], [onError] or [onSettled] to the
///   constructor, and the cache to the client, to handle every query's
///   outcome in one place — the usual home of a global error report.
/// * **Events.** [subscribe] delivers a [QueryCacheEvent] for every query
///   that is added, removed or updated — for logging, devtools or a
///   persistence layer.
/// * **Lookup.** [find], [findAll] and [queries] return the [Query] entries
///   themselves, with their full state.
///
/// ```dart
/// final client = QueryClient(
///   queryCache: QueryCache(
///     onError: (error, stackTrace, query) {
///       // Only background refreshes: a first load shows its own error.
///       if (query.state.hasData) {
///         showSnackBar('Could not refresh ${query.queryKey}: $error');
///       }
///     },
///   ),
/// );
/// ```
///
/// {@category Caches}
class QueryCache extends Subscribable<void Function(QueryCacheEvent event)>
    implements QueryCacheRef {
  /// Creates an empty cache with the given cache-wide hooks, all optional.
  /// A [QueryClient] constructs one of these when none is passed to it.
  ///
  /// The hooks are final: there is no setter to swap a handler later, so
  /// "which handler ran for this fetch" never depends on *when* it was set.
  /// A handler that has to change while the app runs is a hook that closes
  /// over something you own —
  ///
  /// ```dart
  /// void Function(Object)? report;
  /// final cache = QueryCache(onError: (error, _, __) => report?.call(error));
  /// ```
  ///
  /// — which keeps the swap where its owner can see it. A cache built for a
  /// *scope* rather than for the app is the other answer: a `QueryClient` is
  /// cheap, and a second one with its own cache is what a subtree with its own
  /// error handling wants. For watching rather than handling, there is
  /// [subscribe], which needs no hook at all.
  ///
  /// TanStack Query takes the same three hooks as its `QueryCache` config.
  QueryCache({this.onSuccess, this.onError, this.onSettled});

  /// Runs after any query's fetch succeeds, with the fetched data and the
  /// query. Unset by default.
  ///
  /// It runs once per fetch, however many observers share that fetch, and
  /// after the data has been written to the cache, so `query.state` already
  /// holds it. Only fetches run it: a manual write with `setQueryData` does
  /// not. Queries have no per-observer success callback; this hook, or
  /// awaiting the fetch (`client.query`, `refetch`), is where such code goes.
  /// A throw from the hook is reported to the current zone and does not fail
  /// the fetch.
  final void Function(Object? data, Query<Object?> query)? onSuccess;

  /// Runs after any query's fetch fails for good — once retries are
  /// exhausted, not per attempt — with the error, its stack trace and the
  /// query. Unset by default.
  ///
  /// It runs once per failed fetch, however many observers share it, after
  /// the error has been written to the query's state; data from an earlier
  /// success is still in `query.state.data` then, which tells a failed
  /// background refresh from a failed first load. A cancel that is not
  /// silent (`cancelQueries(revert: false)`, or a bare `Query.cancel()`) is
  /// such a failure and runs it with a `CancelledError`; the default
  /// reverting cancel records no error and runs nothing. A throw from the
  /// hook is reported to the current zone and does not change the fetch's
  /// outcome.
  final void Function(
      Object error, StackTrace stackTrace, Query<Object?> query)? onError;

  /// Runs after any query's fetch settles, success or failure, with whichever
  /// of data and error applies: after a failure, `data` is what the query
  /// still holds from an earlier success, or `null`. Runs right after
  /// [onSuccess] or [onError], once per fetch, and is skipped when that hook
  /// throws; a fetch whose cancel records no error runs neither. Unset by
  /// default.
  final void Function(
    Object? data,
    Object? error,
    StackTrace? stackTrace,
    Query<Object?> query,
  )? onSettled;

  final Map<QueryKey, Query<Object?>> _queries = <QueryKey, Query<Object?>>{};

  /// The query for [options]'s key, creating it if it does not exist yet.
  ///
  /// [state] is how a persistence layer restores a saved entry; it is used
  /// only when the query is created here, and ignored when the key already
  /// has one. A `success` state must carry data (`hasData`), or the first
  /// result built from it would fail on a cast; one without is refused with
  /// an [ArgumentError] in every build mode, as `Query.setState` refuses it,
  /// so the mistake surfaces here and not later in an observer.
  ///
  /// A restored [QueryState.fetchStatus] is normalised to
  /// [FetchStatus.idle]. A snapshot taken mid-fetch says `fetching` or
  /// `paused`, but no fetch survives the process it ran in: installed
  /// verbatim it would make a query nothing is doing count towards
  /// `QueryClient.isFetching()`, keep it out of garbage collection for
  /// good, and leave a `paused` one that no reconnect could resume. TanStack
  /// Query's hydration applies the same rule. [Query.setState] does *not*
  /// normalise: it is the other half of a restore, the merge into a query
  /// that already exists, and there a fetch may really be running.
  Query<TQueryData> build<TQueryData>(
    QueryClient client,
    DefaultedQueryOptions<TQueryData> options, {
    QueryState<TQueryData>? state,
  }) {
    state?.validate();
    final existing = get<TQueryData>(options.queryKey);
    if (existing != null) {
      return existing;
    }

    final query = Query<TQueryData>(
      client: client,
      cache: this,
      queryKey: options.queryKey,
      options: options,
      state: state?.fetchStatus == FetchStatus.idle
          ? state
          : state?.copyWith(fetchStatus: FetchStatus.idle),
    );
    // InitialData.compute may synchronously populate this key. That entry,
    // rather than the losing constructor, is the cache's canonical query.
    final canonical = get<TQueryData>(options.queryKey);
    if (canonical != null) {
      query.markRemoved();
      return canonical;
    }
    add(query);
    return query;
  }

  /// Puts [query] into the cache under its key and emits [QueryAdded]. A key
  /// already present keeps the query it has; nothing is replaced. [build] is
  /// the usual way in — this is for a query constructed by hand.
  ///
  /// A previously removed instance is terminal and throws [StateError]; use
  /// [build] to create a fresh entry for the same key.
  void add(Query<Object?> query) {
    if (query.isRemoved) {
      throw StateError(
          'A removed Query cannot be added again: ${query.queryKey}');
    }
    if (!_queries.containsKey(query.queryKey)) {
      _queries[query.queryKey] = query;
      notify(QueryAdded(query));
    }
  }

  /// Takes [query] out of the cache, cancelling its fetch silently and stopping
  /// its collection timer, then emits [QueryRemoved]. The key's slot is only
  /// cleared when it still holds this very query — a stale reference cannot
  /// evict its successor. `QueryClient.removeQueries` does the same for
  /// every query matching a filter.
  void remove(Query<Object?> query) {
    final existing = _queries[query.queryKey];
    if (existing != null) {
      query.markRemoved();
      if (identical(existing, query)) {
        _queries.remove(query.queryKey);
      }
      notify(QueryRemoved(query));
    }
  }

  /// Removes every query, one [QueryRemoved] each.
  ///
  /// Prefer `QueryClient.clear`: it calls this together with the mutation
  /// cache's, inside one `notifyManager.batch`, so a deferred subscriber gets
  /// one flush for the call. The notify manager belongs to the client, not
  /// to this cache, so calling this directly delivers the removals
  /// unbatched.
  void clear() {
    for (final query in queries) {
      remove(query);
    }
  }

  /// The query stored under [queryKey], or `null` if there is none.
  ///
  /// Throws [QueryDataTypeError] if it holds a different data type — a
  /// *different* type, not a subtype: `is Query<T>` would let a `Query<int>`
  /// through as a `Query<int?>` or a `Query<num>`, and the first write of
  /// options typed for the wider type then failed deep inside the observer
  /// with a raw `TypeError`. One key, one exact type.
  Query<TQueryData>? get<TQueryData>(QueryKey queryKey) {
    final query = _queries[queryKey];
    if (query == null) {
      return null;
    }
    if (query.dataType == TQueryData) {
      return query as Query<TQueryData>;
    }
    throw QueryDataTypeError(queryKey, TQueryData, query.dataType);
  }

  /// The query stored under [queryKey] whatever its data type, for the one
  /// caller that asks the entry what it can hold rather than naming its type
  /// (`QueryClient.setQueryData`).
  @internal
  Query<Object?>? peek(QueryKey queryKey) => _queries[queryKey];

  /// Every query in the cache, as a copy: safe to iterate while removing.
  /// TanStack Query calls this `getAll`.
  List<Query<Object?>> get queries => List<Query<Object?>>.of(_queries.values);

  /// Every query matching [filters], in insertion order — all of them when the
  /// filters are empty. A `queryKey` filter matches as a prefix unless
  /// `exact` is true.
  List<Query<Object?>> findAll({
    QueryFilters filters = const QueryFilters(),
  }) =>
      queries.where(filters.matches).toList();

  /// The first query matching [filters], or `null`. Unlike [findAll], an
  /// unset `exact` means an exact key match here, so
  /// `find(filters: QueryFilters(queryKey: key))` finds the query stored
  /// under `key` itself.
  Query<Object?>? find({required QueryFilters filters}) {
    // A copy, like `findAll`: a predicate may remove the query it is shown.
    for (final query in queries) {
      if (filters.matches(query, exactByDefault: true)) {
        return query;
      }
    }
    return null;
  }

  /// Delivers [event] to every listener added with [subscribe].
  ///
  /// Each listener is isolated, as observer listeners are: a throw is
  /// reported to the zone and the rest still run, so a devtools or logging
  /// subscriber that throws cannot break the fetch whose event it was
  /// handling.
  void notify(QueryCacheEvent event) =>
      notifyListeners((listener) => listener(event));

  /// Emits [QueryObserverAdded]. Called by [Query.addObserver] through
  /// [QueryCacheRef]; not for user code.
  @internal
  @override
  void onQueryObserverAdded(Query<Object?> query, QueryObserverRef observer) =>
      notify(QueryObserverAdded(query, observer));

  /// Emits [QueryObserverRemoved]. Called by [Query.removeObserver] through
  /// [QueryCacheRef]; not for user code.
  @internal
  @override
  void onQueryObserverRemoved(
    Query<Object?> query,
    QueryObserverRef observer,
  ) =>
      notify(QueryObserverRemoved(query, observer));

  /// Emits [QueryObserverOptionsUpdated]. Called by the observer's `setOptions`
  /// when it stays on the same query; not for user code.
  @internal
  void notifyObserverOptionsUpdated(
    Query<Object?> query,
    QueryObserverRef observer,
  ) =>
      notify(QueryObserverOptionsUpdated(query, observer));

  /// Emits [QueryObserverResultsUpdated]. Called by the observer after it has
  /// notified its own listeners; not for user code.
  @internal
  void notifyObserverResultsUpdated(Query<Object?> query) =>
      notify(QueryObserverResultsUpdated(query));

  /// Every query reacts to the app coming back to the foreground. Setting
  /// [refetchQueries] to false still allows paused requests to continue.
  void onFocus({bool refetchQueries = true}) {
    for (final query in queries) {
      query.onFocus(refetchQueries: refetchQueries);
    }
  }

  /// Every query reacts to the device coming back online.
  void onOnline() {
    for (final query in queries) {
      query.onOnline();
    }
  }

  @override
  @internal
  void onQueryStateUpdated(Query<Object?> query, QueryAction action) =>
      notify(QueryUpdated(query, action));

  @override
  @internal
  void onQueryRemovalRequested(Query<Object?> query) => remove(query);

  @override
  @internal
  void onQueryFetchSuccess(Query<Object?> query, Object? data) {
    onSuccess?.call(data, query);
    onSettled?.call(
        data, query.state.error, query.state.errorStackTrace, query);
  }

  @override
  @internal
  void onQueryFetchError(
    Query<Object?> query,
    Object error,
    StackTrace stackTrace,
  ) {
    onError?.call(error, stackTrace, query);
    onSettled?.call(
      query.state.hasData ? query.state.data : null,
      error,
      stackTrace,
      query,
    );
  }
}
