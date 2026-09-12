/// Port of `query-core/src/queryCache.ts` at upstream `50680b98c`.
library;

import 'package:meta/meta.dart';

import 'filters.dart';
import 'query.dart';
import 'query_client.dart';
import 'query_key.dart';
import 'query_options.dart';
import 'query_state.dart';
import 'subscribable.dart';

/// Something happened to a query in the cache.
@immutable
sealed class QueryCacheEvent {
  const QueryCacheEvent(this.query);

  /// The query the event is about. Typed as `Query<Object?>`, since a cache
  /// listener sees every key; read `dataType` or `get<T>` it from the cache to
  /// recover the concrete type.
  final Query<Object?> query;
}

/// A query was created and put into the cache, by [QueryCache.build] or
/// [QueryCache.add]. Upstream's `added` event.
final class QueryAdded extends QueryCacheEvent {
  /// Creates the event for [query].
  const QueryAdded(super.query);
}

/// A query left the cache: it was garbage-collected, or removed through
/// `QueryClient.removeQueries`, [QueryCache.remove] or [QueryCache.clear].
/// Upstream's `removed` event.
final class QueryRemoved extends QueryCacheEvent {
  /// Creates the event for [query].
  const QueryRemoved(super.query);
}

/// A query's state changed. Emitted for every dispatched [QueryAction] —
/// fetch, success, error, invalidate, pause, and the rest — so this is the
/// event a devtools panel or a persister keys its work off. Upstream's
/// `updated` event.
final class QueryUpdated extends QueryCacheEvent {
  /// Creates the event for [query], carrying the [action] that changed it.
  const QueryUpdated(super.query, this.action);

  /// The transition that produced the query's new state. Sealed, so a listener
  /// can `switch` over it exhaustively.
  final QueryAction action;
}

/// An observer subscribed to the query. Emitted the moment the observer
/// attaches, which is also what cancels the query's pending collection.
/// Upstream's `observerAdded` event.
final class QueryObserverAdded extends QueryCacheEvent {
  /// Creates the event for [query] and the [observer] that attached.
  const QueryObserverAdded(super.query, this.observer);

  /// The observer that attached. Read-only from outside: it is an identity to
  /// hold and compare, not something to drive.
  final QueryObserverRef observer;
}

/// An observer unsubscribed from the query. Emitted after the observer has
/// been detached — and, when it was the last one, after the retryer has been
/// told to stop retrying and the collection timer has been armed. Upstream's
/// `observerRemoved` event.
final class QueryObserverRemoved extends QueryCacheEvent {
  /// Creates the event for [query] and the [observer] that detached.
  const QueryObserverRemoved(super.query, this.observer);

  /// The observer that detached. Read-only from outside.
  final QueryObserverRef observer;
}

/// An observer's options were replaced while it stayed attached to the same
/// query — a rebuild that changed `staleTime`, `enabled` or a callback, say.
/// Not emitted when the new options move the observer to a different key;
/// that is a removal and an addition. Upstream's `observerOptionsUpdated`
/// event.
final class QueryObserverOptionsUpdated extends QueryCacheEvent {
  /// Creates the event for [query] and the [observer] whose options changed.
  const QueryObserverOptionsUpdated(super.query, this.observer);

  /// The observer whose options changed. Read-only from outside.
  final QueryObserverRef observer;
}

/// An observer of the query delivered a new result to its listeners. Emitted
/// once per delivery, after the listeners have run, so a devtools panel can
/// mirror what the UI just saw. Upstream's `observerResultsUpdated` event.
final class QueryObserverResultsUpdated extends QueryCacheEvent {
  /// Creates the event for [query].
  const QueryObserverResultsUpdated(super.query);
}

/// Thrown when a query is read as one data type but holds another — or when
/// an erased default (`QueryDefaults.queryFn`, `structuralSharing`,
/// `MutationDefaults.mutationFn`) hands back a value of the wrong type.
///
/// Upstream casts blindly and TypeScript cannot catch it; here the mismatch is
/// always a bug, so it is loud rather than a silent `null`
/// (https://github.com/KoTTi97/flutter_query/issues/7). It is thrown
/// *synchronously*, from the call that reads or writes the key —
/// `getQueryData`, `setQueryData`, `getQueriesData`, `updateQueriesData`,
/// `QueryClient.query` and an observer's `setOptions` all throw before any
/// future exists; only the erased-default case surfaces through the fetch or
/// mutation the default ran in, as its error. [queryKey] is `null` when the
/// default that produced the value has no key to name: a sharing hook sees
/// only the data, and a mutation function only its variables.
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
    // `setQueryData(key, 'x')` against a `Query<String?>`: the argument
    // inferred the non-nullable type, and naming the query's type is the
    // cure (ninth review, 2026-09-10, C23).
    final cure = '$actual' == '$expected?'
        ? " The query's type is nullable and the type argument inferred the "
            'non-nullable one: name it, as in setQueryData<$actual>(key, '
            'value).'
        : '';
    return 'Query $key holds $actual but was used as $expected. One key is '
        'being used with two data types.$cure';
  }
}

/// Every query, keyed by [QueryKey].
class QueryCache extends Subscribable<void Function(QueryCacheEvent event)>
    implements QueryCacheRef {
  /// Creates an empty cache. The three hooks are optional and cache-wide; a
  /// [QueryClient] constructs one of these when none is passed to it.
  ///
  /// **The hooks are final, and that is the decision** (C59,
  /// https://github.com/KoTTi97/flutter_query/issues/66). Upstream keeps them
  /// in a `public config` field a caller could reassign; nothing in
  /// `query-core` or its tests does, and a settable hook would make "which
  /// handler ran for this fetch" a question about *when* it was set. A handler
  /// that has to change while the app runs is a hook that closes over
  /// something you own —
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
  QueryCache({this.onSuccess, this.onError, this.onSettled});

  /// Cache-wide hooks, upstream's `QueryCacheConfig`.
  final void Function(Object? data, Query<Object?> query)? onSuccess;

  /// Runs after any query's fetch fails for good — once retries are
  /// exhausted, not per attempt — with the error and the query. Upstream's
  /// `QueryCacheConfig.onError`.
  final void Function(
      Object error, StackTrace stackTrace, Query<Object?> query)? onError;

  /// Runs after any query's fetch settles, success or failure, with whichever
  /// of data and error applies. Runs after [onSuccess] or [onError].
  /// Upstream's `QueryCacheConfig.onSettled`.
  final void Function(
    Object? data,
    Object? error,
    StackTrace? stackTrace,
    Query<Object?> query,
  )? onSettled;

  final Map<QueryKey, Query<Object?>> _queries = <QueryKey, Query<Object?>>{};

  /// The query for [options]'s key, creating it if it does not exist yet.
  ///
  /// [state] is the door a persistence layer restores through; it is used
  /// only when the query is created here. A `success` state must carry data
  /// (`hasData`), or the first result built from it would fail on a cast;
  /// one without is refused with an [ArgumentError] in every build mode, as
  /// `Query.setState` refuses it. An `assert` let a release build accept the
  /// state and fail in the next observer's constructor with `type 'Null' is
  /// not a subtype of type 'int'` (ninth review, 2026-09-10, C8).
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
      state: state,
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
  /// the usual way in — this is upstream's `add`, for a query constructed by
  /// hand.
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
  /// evict its successor. Upstream's `remove`.
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

  /// Removes every query, one [QueryRemoved] each. `QueryClient.clear` calls
  /// this together with the mutation cache's.
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

  /// Every query in the cache, as a copy: safe to iterate while removing.
  /// Upstream's `getAll`.
  List<Query<Object?>> get queries => List<Query<Object?>>.of(_queries.values);

  /// Every query matching [filters], in insertion order — all of them when the
  /// filters are empty. Partial key matching by default, as upstream's
  /// `findAll`.
  List<Query<Object?>> findAll({
    QueryFilters filters = const QueryFilters(),
  }) =>
      queries.where(filters.matches).toList();

  /// The first matching query. An unset `exact` means an exact match here,
  /// as upstream's `find` defaults `{ exact: true, ...filters }`.
  Query<Object?>? find({required QueryFilters filters}) {
    // A copy, like `findAll`: a predicate may remove the query it is shown.
    for (final query in queries) {
      if (filters.matches(query, exactByDefault: true)) {
        return query;
      }
    }
    return null;
  }

  /// Each listener is isolated, as observer listeners are: a throw is
  /// reported to the zone and the rest still run. Unisolated, a devtools or
  /// logging subscriber that threw on a `failed` action blew up the retryer's
  /// loop and left the fetch pending forever (fourth review, 2026-09-09).
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
