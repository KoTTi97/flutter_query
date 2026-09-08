import 'package:meta/meta.dart';

import 'mutation.dart';
import 'mutation_options.dart';
import 'mutation_state.dart';
import 'option_values.dart';
import 'query.dart';
import 'query_key.dart';

/// Which queries a filter reaches, by whether anything is watching them.
enum QueryTypeFilter {
  all,

  /// Queries with at least one enabled observer.
  active,

  /// Queries nothing is watching, or whose observers are all disabled.
  inactive,
}

/// Selects a subset of the cache.
///
/// Every client method that acts on more than one query takes one of these —
/// invalidate, refetch, cancel, remove, reset. An empty filter matches
/// everything, so `invalidateQueries()` invalidates the whole cache.
@immutable
class QueryFilters {
  const QueryFilters({
    this.queryKey,
    this.exact = false,
    this.type,
    this.stale,
    this.fetchStatus,
    this.predicate,
  });

  /// Matches queries whose key starts with this one, unless [exact].
  ///
  /// Prefix matching is what makes key hierarchies useful: a filter of
  /// `['sensors']` reaches `['sensors', 'detail', 3]` and everything else
  /// beneath it.
  final QueryKey? queryKey;

  /// Requires the whole key to be equal rather than a prefix.
  final bool exact;

  /// Null and [QueryTypeFilter.all] both match everything, but they are not
  /// interchangeable: `invalidateQueries` falls back to refetching *active*
  /// queries only when the filter says nothing about type, so "unset" has to
  /// stay distinguishable from an explicit "all".
  final QueryTypeFilter? type;

  /// Matches only stale (true) or only fresh (false) queries.
  final bool? stale;

  final FetchStatus? fetchStatus;

  /// An arbitrary extra condition, applied after all of the above.
  final bool Function(Query<Object?> query)? predicate;

  /// Whether this filter matches nothing in particular, and so matches
  /// everything.
  bool get isEmpty =>
      queryKey == null &&
      !exact &&
      type == null &&
      stale == null &&
      fetchStatus == null &&
      predicate == null;

  bool matches(Query<Object?> query) {
    final key = queryKey;
    if (key != null) {
      if (exact) {
        if (query.queryKey != key) {
          return false;
        }
      } else if (!key.isPrefixOf(query.queryKey)) {
        return false;
      }
    }

    final type = this.type;
    if (type != null && type != QueryTypeFilter.all) {
      final isActive = query.isActive();
      if (type == QueryTypeFilter.active && !isActive) {
        return false;
      }
      if (type == QueryTypeFilter.inactive && isActive) {
        return false;
      }
    }

    final stale = this.stale;
    if (stale != null && query.isStale() != stale) {
      return false;
    }

    if (fetchStatus != null && fetchStatus != query.state.fetchStatus) {
      return false;
    }

    final predicate = this.predicate;
    if (predicate != null && !predicate(query)) {
      return false;
    }

    return true;
  }

  QueryFilters copyWith({
    QueryKey? queryKey,
    bool? exact,
    QueryTypeFilter? type,
    bool? stale,
    FetchStatus? fetchStatus,
    bool Function(Query<Object?> query)? predicate,
  }) {
    return QueryFilters(
      queryKey: queryKey ?? this.queryKey,
      exact: exact ?? this.exact,
      type: type ?? this.type,
      stale: stale ?? this.stale,
      fetchStatus: fetchStatus ?? this.fetchStatus,
      predicate: predicate ?? this.predicate,
    );
  }
}

/// Which of the queries an invalidation marked should refetch right away.
///
/// Separate from [QueryTypeFilter] because "which queries to invalidate" and
/// "which of those to refetch now" are different questions: invalidating the
/// whole cache while refetching only what is on screen is the common case.
enum QueryRefetchType {
  all,
  active,
  inactive,

  /// Mark them stale, refetch nothing.
  none,
}

/// Selects a subset of the mutation cache.
///
/// Mutations have no fetch status and no active/inactive split — a mutation is
/// either running or it is not — so this is the smaller sibling of
/// [QueryFilters].
@immutable
class MutationFilters {
  const MutationFilters({
    this.mutationKey,
    this.exact = false,
    this.status,
    this.predicate,
  });

  /// Matches mutations whose key starts with this one, unless [exact].
  final MutationKey? mutationKey;

  final bool exact;

  final MutationStatus? status;

  final bool Function(Mutation<Object?, Object?, Object?> mutation)? predicate;

  bool get isEmpty =>
      mutationKey == null && !exact && status == null && predicate == null;

  bool matches(Mutation<Object?, Object?, Object?> mutation) {
    final key = mutationKey;
    if (key != null) {
      final mutationOwnKey = mutation.options.mutationKey;
      if (mutationOwnKey == null) {
        return false;
      }
      if (exact) {
        if (mutationOwnKey != key) {
          return false;
        }
      } else if (!key.isPrefixOf(mutationOwnKey)) {
        return false;
      }
    }

    if (status != null && status != mutation.state.status) {
      return false;
    }

    final predicate = this.predicate;
    if (predicate != null && !predicate(mutation)) {
      return false;
    }

    return true;
  }

  MutationFilters copyWith({
    MutationKey? mutationKey,
    bool? exact,
    MutationStatus? status,
    bool Function(Mutation<Object?, Object?, Object?> mutation)? predicate,
  }) {
    return MutationFilters(
      mutationKey: mutationKey ?? this.mutationKey,
      exact: exact ?? this.exact,
      status: status ?? this.status,
      predicate: predicate ?? this.predicate,
    );
  }
}
