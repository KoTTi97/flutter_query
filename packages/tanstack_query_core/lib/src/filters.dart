/// Port of the filter half of `query-core/src/utils.ts` at upstream
/// `50680b98c`.
library;

import 'package:meta/meta.dart';

import 'mutation.dart';
import 'query.dart';
import 'query_key.dart';
import 'query_state.dart';

/// Which queries a filtered operation applies to.
enum QueryTypeFilter { all, active, inactive }

/// Selects a set of queries.
///
/// Every field is nullable-means-unset, so a default-constructed
/// [QueryFilters] matches everything — the same convention the options model
/// uses (https://github.com/KoTTi97/flutter_query/issues/17).
@immutable
class QueryFilters {
  const QueryFilters({
    this.queryKey,
    this.exact = false,
    this.type = QueryTypeFilter.all,
    this.stale,
    this.fetchStatus,
    this.status,
    this.predicate,
  });

  /// Matched as a prefix unless [exact] is set.
  final QueryKey? queryKey;
  final bool exact;
  final QueryTypeFilter type;
  final bool? stale;
  final FetchStatus? fetchStatus;
  final QueryStatus? status;

  /// Receives the erased query: a predicate spanning mixed data types cannot
  /// be given a useful type parameter.
  final bool Function(Query<Object?> query)? predicate;

  bool matches(Query<Object?> query) {
    final queryKey = this.queryKey;
    if (queryKey != null && !query.queryKey.matches(queryKey, exact: exact)) {
      return false;
    }

    switch (type) {
      case QueryTypeFilter.active:
        if (!query.isActive()) return false;
      case QueryTypeFilter.inactive:
        if (query.isActive()) return false;
      case QueryTypeFilter.all:
        break;
    }

    final stale = this.stale;
    if (stale != null && query.isStale() != stale) {
      return false;
    }

    final fetchStatus = this.fetchStatus;
    if (fetchStatus != null && query.state.fetchStatus != fetchStatus) {
      return false;
    }

    final status = this.status;
    if (status != null && query.state.status != status) {
      return false;
    }

    final predicate = this.predicate;
    if (predicate != null && !predicate(query)) {
      return false;
    }

    return true;
  }
}

/// Selects a set of mutations.
@immutable
class MutationFilters {
  const MutationFilters({
    this.mutationKey,
    this.exact = false,
    this.status,
    this.predicate,
  });

  final QueryKey? mutationKey;
  final bool exact;
  final MutationStatus? status;
  final bool Function(Mutation<Object?, Object?, Object?> mutation)? predicate;

  bool matches(Mutation<Object?, Object?, Object?> mutation) {
    final mutationKey = this.mutationKey;
    if (mutationKey != null) {
      final key = mutation.options.mutationKey;
      if (key == null || !key.matches(mutationKey, exact: exact)) {
        return false;
      }
    }

    final status = this.status;
    if (status != null && mutation.state.status != status) {
      return false;
    }

    final predicate = this.predicate;
    if (predicate != null && !predicate(mutation)) {
      return false;
    }

    return true;
  }
}
