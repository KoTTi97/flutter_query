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
  final Query<Object?> query;
}

final class QueryAdded extends QueryCacheEvent {
  const QueryAdded(super.query);
}

final class QueryRemoved extends QueryCacheEvent {
  const QueryRemoved(super.query);
}

final class QueryUpdated extends QueryCacheEvent {
  const QueryUpdated(super.query, this.action);
  final QueryAction action;
}

final class QueryObserverAdded extends QueryCacheEvent {
  const QueryObserverAdded(super.query, this.observer);
  final QueryObserverRef observer;
}

final class QueryObserverRemoved extends QueryCacheEvent {
  const QueryObserverRemoved(super.query, this.observer);
  final QueryObserverRef observer;
}

final class QueryObserverOptionsUpdated extends QueryCacheEvent {
  const QueryObserverOptionsUpdated(super.query, this.observer);
  final QueryObserverRef observer;
}

final class QueryObserverResultsUpdated extends QueryCacheEvent {
  const QueryObserverResultsUpdated(super.query);
}

/// Thrown when a query is read as one data type but holds another.
///
/// Upstream casts blindly and TypeScript cannot catch it; here the mismatch is
/// always a bug, so it is loud rather than a silent `null`
/// (https://github.com/KoTTi97/flutter_query/issues/7).
final class QueryDataTypeError implements Exception {
  const QueryDataTypeError(this.queryKey, this.expected, this.actual);

  final QueryKey queryKey;
  final Type expected;
  final Type actual;

  @override
  String toString() =>
      'Query $queryKey holds $actual but was read as $expected. One key is '
      'being used with two data types.';
}

/// Every query, keyed by [QueryKey].
class QueryCache extends Subscribable<void Function(QueryCacheEvent event)>
    implements QueryCacheRef {
  QueryCache({this.onSuccess, this.onError, this.onSettled});

  /// Cache-wide hooks, upstream's `QueryCacheConfig`.
  final void Function(Object? data, Query<Object?> query)? onSuccess;
  final void Function(
      Object error, StackTrace stackTrace, Query<Object?> query)? onError;
  final void Function(
    Object? data,
    Object? error,
    StackTrace? stackTrace,
    Query<Object?> query,
  )? onSettled;

  final Map<QueryKey, Query<Object?>> _queries = <QueryKey, Query<Object?>>{};

  /// The query for [options]'s key, creating it if it does not exist yet.
  Query<TQueryData> build<TQueryData>(
    QueryClient client,
    DefaultedQueryOptions<TQueryData> options, {
    QueryState<TQueryData>? state,
  }) {
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
    add(query);
    return query;
  }

  void add(Query<Object?> query) {
    if (!_queries.containsKey(query.queryKey)) {
      _queries[query.queryKey] = query;
      notify(QueryAdded(query));
    }
  }

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

  void clear() {
    for (final query in queries) {
      remove(query);
    }
  }

  /// The query stored under [queryKey], or `null` if there is none.
  ///
  /// Throws [QueryDataTypeError] if it holds a different data type.
  Query<TQueryData>? get<TQueryData>(QueryKey queryKey) {
    final query = _queries[queryKey];
    if (query == null) {
      return null;
    }
    if (query is Query<TQueryData>) {
      return query;
    }
    throw QueryDataTypeError(queryKey, TQueryData, query.runtimeType);
  }

  List<Query<Object?>> get queries => List<Query<Object?>>.of(_queries.values);

  List<Query<Object?>> findAll([
    QueryFilters filters = const QueryFilters(),
  ]) =>
      queries.where(filters.matches).toList();

  Query<Object?>? find(QueryFilters filters) {
    for (final query in _queries.values) {
      if (filters.matches(query)) {
        return query;
      }
    }
    return null;
  }

  void notify(QueryCacheEvent event) {
    for (final listener in List.of(listeners)) {
      listener(event);
    }
  }

  @internal
  void notifyObserverAdded(Query<Object?> query, QueryObserverRef observer) =>
      notify(QueryObserverAdded(query, observer));

  @internal
  void notifyObserverRemoved(Query<Object?> query, QueryObserverRef observer) =>
      notify(QueryObserverRemoved(query, observer));

  @internal
  void notifyObserverOptionsUpdated(
    Query<Object?> query,
    QueryObserverRef observer,
  ) =>
      notify(QueryObserverOptionsUpdated(query, observer));

  @internal
  void notifyObserverResultsUpdated(Query<Object?> query) =>
      notify(QueryObserverResultsUpdated(query));

  /// Every query reacts to the app coming back to the foreground.
  void onFocus() {
    for (final query in queries) {
      query.onFocus();
    }
  }

  /// Every query reacts to the device coming back online.
  void onOnline() {
    for (final query in queries) {
      query.onOnline();
    }
  }

  @override
  void onQueryStateUpdated(Query<Object?> query, QueryAction action) =>
      notify(QueryUpdated(query, action));

  @override
  void onQueryRemovalRequested(Query<Object?> query) => remove(query);

  @override
  void onQueryFetchSuccess(Query<Object?> query, Object? data) {
    onSuccess?.call(data, query);
    onSettled?.call(
        data, query.state.error, query.state.errorStackTrace, query);
  }

  @override
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
