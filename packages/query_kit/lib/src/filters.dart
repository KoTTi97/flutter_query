/// The filters that select queries and mutations for the client's bulk
/// operations and the caches' `find`/`findAll`.
library;

import 'package:meta/meta.dart';

import 'mutation.dart';
import 'query.dart';
import 'query_key.dart';
import 'query_state.dart';

/// Which queries a filtered operation applies to, by whether anything is
/// observing them: the value of [QueryFilters.type].
///
/// Leaving [QueryFilters.type] unset is the same as [QueryTypeFilter.all].
///
/// {@category Filters}
enum QueryTypeFilter {
  /// Every query, observed or not.
  all,

  /// Queries with at least one enabled observer — typically, queries some
  /// widget on screen is showing.
  active,

  /// Queries with no enabled observer: nothing observes them, or every
  /// observer is disabled.
  inactive,
}

/// Which queries `invalidateQueries` refetches once it has marked them stale.
/// [RefetchType.none] marks without refetching anything.
///
/// Unset, `invalidateQueries` refetches the active ones, unless the filters
/// name a `type` of their own.
///
/// {@category Filters}
enum RefetchType {
  /// Refetch the invalidated queries that have an enabled observer. The
  /// default, unless the filters name a `type` of their own.
  active,

  /// Refetch only the invalidated queries nobody is observing.
  inactive,

  /// Refetch every invalidated query.
  all,

  /// Mark stale and refetch nothing; observers pick it up on their next
  /// trigger.
  none,
}

/// Selects a set of queries from the cache.
///
/// Passed as `filters:` to the client's bulk operations —
/// `invalidateQueries`, `refetchQueries`, `cancelQueries`, `removeQueries`,
/// `resetQueries`, `isFetching` and the rest — and to `QueryCache.find` and
/// `QueryCache.findAll`. A query must match every field that is set:
///
/// * [queryKey] — the key, as a prefix unless [exact] is true.
/// * [exact] — whether [queryKey] must match the whole key.
/// * [type] — observed queries, unobserved ones, or both.
/// * [stale] — stale or fresh queries.
/// * [fetchStatus] — fetching, paused or idle queries.
/// * [status] — pending, successful or failed queries.
/// * [predicate] — any test of your own over the query.
///
/// Every field is optional and `null` means "do not filter on this", so an
/// empty `QueryFilters()` matches every query in the cache.
///
/// ```dart
/// // Every query whose key starts with 'todos': ['todos'],
/// // ['todos', 3], ['todos', {'done': true}], ...
/// await client.invalidateQueries(
///   filters: QueryFilters(queryKey: QueryKey(['todos'])),
/// );
///
/// // Only the one query keyed exactly ['todos'].
/// client.removeQueries(
///   filters: QueryFilters(queryKey: QueryKey(['todos']), exact: true),
/// );
/// ```
///
/// {@category Filters}
@immutable
final class QueryFilters {
  /// Every argument is optional; leave one unset to not filter on it.
  const QueryFilters({
    this.queryKey,
    this.exact,
    this.type,
    this.stale,
    this.fetchStatus,
    this.status,
    this.predicate,
  });

  /// The key to match. By default it is a prefix: `QueryKey(['todos'])`
  /// matches `QueryKey(['todos'])` and `QueryKey(['todos', 3])` alike. Set
  /// [exact] to match only the key itself. Unset matches every key.
  final QueryKey? queryKey;

  /// Whether [queryKey] must equal the whole key rather than a prefix of it.
  ///
  /// Left unset, `findAll` and every bulk operation match by prefix, and
  /// `QueryCache.find` matches exactly. A nullable field is how one value
  /// carries both defaults.
  final bool? exact;

  /// Restricts to active queries (at least one enabled observer), inactive
  /// ones, or both; see [QueryTypeFilter]. Unset means both.
  final QueryTypeFilter? type;

  /// Matches queries whose `isStale()` is this value: `true` for stale
  /// queries, `false` for fresh ones. Unset ignores staleness.
  final bool? stale;

  /// Matches queries in this fetch status: fetching, paused or idle. Unset
  /// ignores it.
  final FetchStatus? fetchStatus;

  /// Matches queries in this status: pending, success or error. Unset
  /// ignores it.
  final QueryStatus? status;

  /// A test of your own, run on each query that passed the other fields.
  /// Unset accepts every query.
  ///
  /// It receives the query as `Query<Object?>`: one filter spans queries of
  /// many data types, so no narrower type parameter fits. Read
  /// `query.queryKey`, `query.state` or `query.meta` from it.
  final bool Function(Query<Object?> query)? predicate;

  /// Whether [query] matches. [exactByDefault] is what an unset [exact]
  /// means to the caller: prefix for the bulk operations, exact for `find`.
  bool matches(Query<Object?> query, {bool exactByDefault = false}) {
    final queryKey = this.queryKey;
    if (queryKey != null &&
        !query.queryKey.matches(queryKey, exact: exact ?? exactByDefault)) {
      return false;
    }

    switch (type) {
      case QueryTypeFilter.active:
        if (!query.isActive()) return false;
      case QueryTypeFilter.inactive:
        if (query.isActive()) return false;
      case QueryTypeFilter.all:
      case null:
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

  @override
  String toString() => describeFilters('QueryFilters', <String, Object?>{
        'queryKey': queryKey,
        'exact': exact,
        'type': type,
        'stale': stale,
        'fetchStatus': fetchStatus,
        'status': status,
        'predicate': predicate,
      });
}

/// Selects a set of mutations from the mutation cache.
///
/// Passed as `filters:` to `MutationCache.find` and `MutationCache.findAll`,
/// to a `MutationStateObserver`, and to `QueryClient.isMutating` (which
/// counts pending mutations only and ignores [status]). A mutation
/// must match every field that is set: [mutationKey] (as a prefix unless
/// [exact] is true), [status], and [predicate]. Every field is optional, so
/// an empty `MutationFilters()` matches every mutation.
///
/// ```dart
/// // Every failed mutation whose key starts with 'todos'.
/// final failed = client.mutationCache.findAll(
///   filters: MutationFilters(
///     mutationKey: QueryKey(['todos']),
///     status: MutationStatus.error,
///   ),
/// );
/// ```
///
/// {@category Filters}
@immutable
final class MutationFilters {
  /// Every argument is optional; leave one unset to not filter on it.
  const MutationFilters({
    this.mutationKey,
    this.exact,
    this.status,
    this.predicate,
  });

  /// The mutation key to match, as a prefix unless [exact] is set. A
  /// mutation without a key never matches a key filter. Unset matches every
  /// mutation.
  final QueryKey? mutationKey;

  /// Whether [mutationKey] must equal the whole key rather than a prefix of
  /// it. Left unset, `findAll` and the bulk operations match by prefix and
  /// `MutationCache.find` matches exactly, as [QueryFilters.exact] does.
  final bool? exact;

  /// Matches mutations in this status: idle, pending, success or error.
  /// Unset ignores it.
  final MutationStatus? status;

  /// A test of your own, run on each mutation that passed the other fields.
  /// Unset accepts every mutation. It receives the mutation with its types
  /// erased, for the same reason as [QueryFilters.predicate].
  final bool Function(Mutation<Object?, Object?, Object?> mutation)? predicate;

  /// Whether [mutation] matches. [exactByDefault] is what an unset [exact]
  /// means to the caller: prefix for the bulk operations, exact for `find`.
  bool matches(
    Mutation<Object?, Object?, Object?> mutation, {
    bool exactByDefault = false,
  }) {
    final mutationKey = this.mutationKey;
    if (mutationKey != null) {
      final key = mutation.options.mutationKey;
      if (key == null ||
          !key.matches(mutationKey, exact: exact ?? exactByDefault)) {
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

  @override
  String toString() => describeFilters('MutationFilters', <String, Object?>{
        'mutationKey': mutationKey,
        'exact': exact,
        'status': status,
        'predicate': predicate,
      });
}

/// `Type(name: value, …)` over the fields of [fields] that are set — what
/// the two filters' `toString` show, so a failing filter reads as what it
/// asked for rather than `Instance of 'QueryFilters'`.
@internal
String describeFilters(String type, Map<String, Object?> fields) {
  final set = fields.entries
      .where((field) => field.value != null)
      .map((field) => '${field.key}: ${field.value}')
      .join(', ');
  return '$type($set)';
}
