import 'package:collection/collection.dart';

import 'filters.dart';
import 'notify_manager.dart';
import 'query.dart';
import 'query_key.dart';
import 'query_options.dart';
import 'query_state.dart';
import 'subscribable.dart';

/// Something that happened to a query in the cache.
sealed class QueryCacheEvent {
  const QueryCacheEvent(this.query);
  final Query<Object?> query;
}

class QueryAdded extends QueryCacheEvent {
  const QueryAdded(super.query);
}

class QueryRemoved extends QueryCacheEvent {
  const QueryRemoved(super.query);
}

class QueryUpdated extends QueryCacheEvent {
  const QueryUpdated(super.query, this.action);
  final QueryAction action;
}

class QueryObserverAdded extends QueryCacheEvent {
  const QueryObserverAdded(super.query, this.observer);
  final QueryObserverRef observer;
}

class QueryObserverRemoved extends QueryCacheEvent {
  const QueryObserverRemoved(super.query, this.observer);
  final QueryObserverRef observer;
}

class QueryObserverResultsUpdated extends QueryCacheEvent {
  const QueryObserverResultsUpdated(super.query);
}

/// An observer was given new options that differ from its previous ones.
class QueryObserverOptionsUpdated extends QueryCacheEvent {
  const QueryObserverOptionsUpdated(super.query, this.observer);
  final QueryObserverRef observer;
}

/// Holds every query, keyed by [QueryKey], and broadcasts what happens to them.
///
/// Upstream keys a `Map` by a hashed string; here [QueryKey] has value
/// equality, so it is the key.
class QueryCache extends Subscribable<void Function(QueryCacheEvent event)>
    implements QueryHost {
  QueryCache({this.onError, this.onSuccess, this.onSettled});

  /// Cache-wide callbacks, useful for logging or global error reporting.
  final void Function(
    Object error,
    StackTrace stackTrace,
    Query<Object?> query,
  )? onError;
  final void Function(Object? data, Query<Object?> query)? onSuccess;
  final void Function(Object? data, Object? error, Query<Object?> query)?
      onSettled;

  final Map<QueryKey, Query<Object?>> _queries = <QueryKey, Query<Object?>>{};

  /// Returns the query for these options, creating it if it does not exist.
  Query<TQueryData> build<TQueryData>(
    DefaultedQueryOptions<TQueryData> options, {
    QueryState<TQueryData>? state,
  }) {
    final existing = get<TQueryData>(options.queryKey);
    if (existing != null) {
      return existing;
    }

    final query = Query<TQueryData>(
      queryKey: options.queryKey,
      host: this,
      options: options,
      initialState: state,
    );
    add(query);
    return query;
  }

  void add(Query<Object?> query) {
    if (_queries.containsKey(query.queryKey)) {
      return;
    }
    _queries[query.queryKey] = query;
    notify(QueryAdded(query));
  }

  void remove(Query<Object?> query) {
    final inCache = _queries[query.queryKey];
    if (inCache == null) {
      return;
    }

    query.destroy();
    // Only drop the entry if it is still this query: a replacement may have
    // taken the key in the meantime.
    if (identical(inCache, query)) {
      _queries.remove(query.queryKey);
    }
    notify(QueryRemoved(query));
  }

  void clear() {
    notifyManager.batch(() {
      for (final query in queries) {
        remove(query);
      }
    });
  }

  /// The query stored under [queryKey], if any. Does not create one.
  ///
  /// Throws [StateError] if the entry holds a different data type, which is
  /// what one key used with two types looks like at runtime.
  Query<TQueryData>? get<TQueryData>(QueryKey queryKey) {
    final query = _queries[queryKey];
    if (query == null) {
      return null;
    }
    if (query is Query<TQueryData>) {
      return query;
    }
    throw StateError(
      'Query $queryKey holds ${query.runtimeType} but was requested as '
      'Query<$TQueryData>. A query key must be used with one data type.',
    );
  }

  List<Query<Object?>> get queries => List.of(_queries.values);

  /// Every query matching [filters]. An empty filter matches all of them.
  List<Query<Object?>> findAll([QueryFilters filters = const QueryFilters()]) {
    final all = queries;
    return filters.isEmpty ? all : all.where(filters.matches).toList();
  }

  /// The first query matching [queryKey].
  ///
  /// Matches the whole key unless [filters] says otherwise — upstream's `find`
  /// defaults to `exact: true` where `findAll` does not. Passing [filters]
  /// replaces that default, so a prefix search needs
  /// `filters: const QueryFilters()`.
  Query<Object?>? find(QueryKey queryKey, {QueryFilters? filters}) {
    final resolved = (filters ?? const QueryFilters(exact: true)).copyWith(
      queryKey: queryKey,
    );
    return queries.firstWhereOrNull(resolved.matches);
  }

  void notify(QueryCacheEvent event) {
    notifyManager.batch(() {
      for (final listener in List.of(listeners)) {
        listener(event);
      }
    });
  }

  /// Tells every query the app came to the foreground.
  void onFocus() {
    notifyManager.batch(() {
      for (final query in queries) {
        query.onFocus();
      }
    });
  }

  /// Tells every query connectivity returned.
  void onOnline() {
    notifyManager.batch(() {
      for (final query in queries) {
        query.onOnline();
      }
    });
  }

  // --- QueryHost -----------------------------------------------------------

  @override
  void onQueryUpdated(Query<Object?> query, QueryAction action) =>
      notify(QueryUpdated(query, action));

  @override
  void onQueryFetchSuccess(Query<Object?> query, Object? data) {
    onSuccess?.call(data, query);
    onSettled?.call(data, query.state.error, query);
  }

  @override
  void onQueryFetchError(
    Query<Object?> query,
    Object error,
    StackTrace stackTrace,
  ) {
    onError?.call(error, stackTrace, query);
    onSettled?.call(query.state.data, error, query);
  }

  @override
  void onQueryRemovalRequested(Query<Object?> query) => remove(query);

  @override
  void onQueryObserverAdded(Query<Object?> query, QueryObserverRef observer) =>
      notify(QueryObserverAdded(query, observer));

  @override
  void onQueryObserverRemoved(
    Query<Object?> query,
    QueryObserverRef observer,
  ) =>
      notify(QueryObserverRemoved(query, observer));
}
