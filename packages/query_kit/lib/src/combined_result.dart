/// Combining the results of queries whose data types differ.
///
/// Port-only: upstream's `useQueries({ combine })` types a heterogeneous tuple,
/// which Dart cannot — a `List` has one element type. A record has one per
/// position, so the combination is a function over a **record of results**,
/// and the observing is left to whatever already produced them. Decided on
/// https://github.com/KoTTi97/flutter_query/issues/82.
library;

import 'package:meta/meta.dart';

import 'query_result.dart';
import 'structural_sharing.dart';

/// What several [QueryResult]s amount to together: nothing to show yet
/// ([CombinedPending]), a source that failed with nothing to show
/// ([CombinedError]), or every source's data run through the combiner
/// ([CombinedData]).
///
/// Built with `combine` on a record of results:
///
/// ```dart
/// final overview = (status, devices).combine(
///   (status, devices) => Overview(status, devices),
/// );
/// ```
///
/// The rules, in order:
///
/// 1. A source that is a [QueryError] **without stale data** makes the whole a
///    [CombinedError] — the first such source in record order. Waiting does
///    not cure it and [retry] is something a user can press, so it wins over
///    a source that is merely still loading.
/// 2. Otherwise a [QueryPending] source makes the whole [CombinedPending].
/// 3. Otherwise every source has data — a [QuerySuccess]'s, or the stale data
///    of a failed refetch — and the whole is [CombinedData]. A failed refetch
///    shows up as [CombinedData.refetchError], not as an error state: content
///    that is on screen is not blanked, as [QueryError.staleData] is not.
@immutable
sealed class CombinedResult<T> {
  const CombinedResult._(this._sources);

  final List<QueryResult<Object?>> _sources;

  /// Whether any source is fetching, first load or background.
  bool get isFetching => _sources.any((source) => source.isFetching);

  /// Whether any source is paused — wanted to fetch and may not, offline.
  bool get isPaused => _sources.any((source) => source.isPaused);

  /// Whether this is a [CombinedPending].
  bool get isPending => this is CombinedPending<T>;

  /// Whether this is a [CombinedError].
  bool get isError => this is CombinedError<T>;

  /// Whether this is a [CombinedData].
  bool get hasData => this is CombinedData<T>;

  /// The combined value, if there is one.
  T? get dataOrNull => switch (this) {
        CombinedData<T>(:final data) => data,
        _ => null,
      };

  /// Refetches every source, as each one's own `refetch` does.
  ///
  /// [cancelRefetch] is passed to every source: `true`, the default as on a
  /// single result, cancels a fetch already running over data and starts
  /// again; `false` joins it. Two combinations that share a source refetch it
  /// once each, so a pull-to-refresh over both fetches it twice unless one of
  /// them passes `false` (release review, 2026-09-23, LIB-5).
  Future<void> refetch({bool cancelRefetch = true}) => Future.wait([
        for (final source in _sources)
          source.refetch(cancelRefetch: cancelRefetch),
      ]);

  /// Refetches the sources that are in error, and only those — an
  /// [OptionalQueryResult.optional] source whose query failed included.
  /// [cancelRefetch] as for [refetch].
  Future<void> retry({bool cancelRefetch = true}) => Future.wait([
        for (final source in _sources)
          if ((_optionalOrigin[source] ?? source).isError)
            source.refetch(cancelRefetch: cancelRefetch),
      ]);

  Object? get _identity;

  /// Equal when the variant, what it carries and the fetch flags are: what a
  /// `buildWhen` or a `ValueNotifier` needs. The sources' `refetch` closures
  /// take no part.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CombinedResult<T> &&
          other.runtimeType == runtimeType &&
          other.isFetching == isFetching &&
          other.isPaused == isPaused &&
          other._identity == _identity;

  @override
  int get hashCode => Object.hash(runtimeType, isFetching, isPaused, _identity);
}

/// At least one source has nothing to show yet, and none has failed outright.
final class CombinedPending<T> extends CombinedResult<T> {
  const CombinedPending._(super.sources) : super._();

  @override
  Object? get _identity => null;

  @override
  String toString() => 'CombinedPending<$T>(isFetching: $isFetching)';
}

/// A source failed and has no data to fall back on.
final class CombinedError<T> extends CombinedResult<T> {
  const CombinedError._(super.sources, this.error, this.stackTrace) : super._();

  /// What the first failed source threw.
  final Object error;

  /// Where [error] was thrown.
  final StackTrace stackTrace;

  @override
  Object? get _identity => error;

  @override
  String toString() => 'CombinedError<$T>($error, isFetching: $isFetching)';
}

/// Every source has data; [data] is what the combiner made of it.
final class CombinedData<T> extends CombinedResult<T> {
  const CombinedData._(
    super.sources,
    this.data,
    this.refetchError,
    this.refetchErrorStackTrace,
  ) : super._();

  /// The combiner's result.
  final T data;

  /// What the first source whose background refetch failed threw; its stale
  /// data is part of [data]. `null` when none did.
  final Object? refetchError;

  /// The stack trace that came with [refetchError].
  final StackTrace? refetchErrorStackTrace;

  /// Whether any source is showing `placeholderData`.
  bool get isPlaceholderData =>
      _sources.any((source) => source.isPlaceholderData);

  /// Whether any source is stale.
  bool get isStale => _sources.any((source) => source.isStale);

  @override
  Object? get _identity => (data, refetchError, isPlaceholderData, isStale);

  @override
  String toString() => 'CombinedData<$T>($data, isFetching: $isFetching, '
      'refetchError: $refetchError)';
}

/// Remembers the last combination, so a combiner runs only when a source's
/// data really changed and an equal result keeps its instance.
///
/// Optional. Without one, `combine` runs the combiner every time it is called
/// — every build, in a widget — which is fine for a constructor call and
/// wasteful for a join over two long lists. Keep one per call site, next to
/// whatever owns the reads (a `State` field, say), and pass it as `memo:`.
///
/// The combiner is skipped when every source's data is the **identical**
/// instance it was last time — which structural sharing makes the normal case
/// for a refetch that changed nothing. When it does run, its result is
/// structurally shared with the previous one, as upstream shares the result of
/// `combine`.
///
/// **The combiner must be a function of the sources and of `keys`, and of
/// nothing else.** A memo cannot see what a closure captures: a combiner that
/// filters by a search text it closes over keeps returning the list for the
/// old text until a source changes. Either do that work on the combined data,
/// after `combine`, or name what the combiner reads — `keys: [search]` —
/// which is compared with `==` and re-runs the combiner when it differs
/// (second integration report, 2026-09-20).
final class CombineMemo<T> {
  /// An empty memo: the first `combine` through it runs the combiner.
  CombineMemo();

  List<Object?>? _inputs;
  List<Object?>? _keys;
  late T _output;

  T _resolve(List<Object?> inputs, List<Object?>? keys, T Function() compute) {
    final previous = _inputs;
    if (previous != null &&
        previous.length == inputs.length &&
        _keysEqual(_keys, keys)) {
      var same = true;
      for (var i = 0; i < inputs.length; i++) {
        if (!identical(previous[i], inputs[i])) {
          same = false;
          break;
        }
      }
      if (same) {
        return _output;
      }
    }
    final computed = compute();
    _output =
        previous == null ? computed : replaceEqualDeep<T>(_output, computed);
    _inputs = inputs;
    _keys = keys == null ? null : List<Object?>.of(keys);
    return _output;
  }

  static bool _keysEqual(List<Object?>? a, List<Object?>? b) {
    if (a == null || b == null) {
      return a == null && b == null;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

CombinedResult<R> _combine<R>(
  List<QueryResult<Object?>> sources,
  R Function() compute,
  CombineMemo<R>? memo,
  List<Object?>? keys,
) {
  for (final source in sources) {
    if (source
        case QueryError(:final error, :final stackTrace, hasStaleData: false)) {
      return CombinedError<R>._(sources, error, stackTrace);
    }
  }
  if (sources.any((source) => source.isPending)) {
    return CombinedPending<R>._(sources);
  }
  Object? refetchError;
  StackTrace? refetchErrorStackTrace;
  for (final source in sources) {
    if (source case QueryError(:final error, :final stackTrace)) {
      refetchError = error;
      refetchErrorStackTrace = stackTrace;
      break;
    }
  }
  final data = memo == null
      ? compute()
      : memo._resolve(
          [for (final source in sources) source.dataOrNull], keys, compute);
  return CombinedData<R>._(sources, data, refetchError, refetchErrorStackTrace);
}

// What an `optional()` stand-in stands in for, so `retry()` still knows that
// the query behind it failed.
final Expando<QueryResult<Object?>> _optionalOrigin =
    Expando<QueryResult<Object?>>('optional origin');

/// A source a combination can do without.
extension OptionalQueryResult<T> on QueryResult<T> {
  /// This result for a combination that must neither wait for it nor fail
  /// with it: an optional feature's endpoint answers 404, and the rest of the
  /// screen is still the rest of the screen.
  ///
  /// With data — a success, or a failed refetch over stale data — this is the
  /// result itself. Without — still loading, disabled, or failed with nothing
  /// to show — it is a success holding `null`, carrying the same fetch status
  /// and `refetch`, so the combination's `isFetching` still sees it and its
  /// `retry()` still refetches it when the query behind it failed.
  ///
  /// ```dart
  /// (tasks, user, avatar.optional()).combine(
  ///   (tasks, user, avatar) => Dashboard(tasks, user, avatar: avatar),
  /// );
  /// ```
  QueryResult<T?> optional() {
    final self = this;
    if (self is QuerySuccess<T> ||
        (self is QueryError<T> && self.hasStaleData)) {
      return self;
    }
    final stand = QuerySuccess<T?>(
      data: null,
      fetchStatus: fetchStatus,
      dataUpdatedAt: dataUpdatedAt,
      errorUpdatedAt: errorUpdatedAt,
      failureCount: failureCount,
      failureReason: failureReason,
      failureStackTrace: failureStackTrace,
      errorUpdateCount: errorUpdateCount,
      consecutiveErrorCount: consecutiveErrorCount,
      isStale: isStale,
      isEnabled: isEnabled,
      isFetched: isFetched,
      isFetchedAfterMount: isFetchedAfterMount,
      isPlaceholderData: false,
      refetch: ({bool cancelRefetch = true}) async =>
          (await refetch(cancelRefetch: cancelRefetch)).optional(),
    );
    _optionalOrigin[stand] = self;
    return stand;
  }
}

/// [combine] over a list of results of one type — a `QueriesController`'s
/// value, say — by the same rules as a record of them.
extension CombineQueryResultList<T> on List<QueryResult<T>> {
  /// What the list amounts to together — see [CombinedResult] for the rules:
  /// a source that failed with nothing to show wins, otherwise one without
  /// data makes it pending, otherwise [combiner] gets every value in order.
  /// An empty list is data. With a [memo], [combiner] must be a function of
  /// the sources and [keys] alone — see [CombineMemo].
  CombinedResult<R> combine<R>(R Function(List<T> values) combiner,
          {CombineMemo<R>? memo, List<Object?>? keys}) =>
      _combine(
          List<QueryResult<Object?>>.of(this),
          () => combiner([for (final source in this) source.dataOrNull as T]),
          memo,
          keys);

  /// This list **and** one more source of another type, as one combination —
  /// the query a dynamic set of queries was derived from, say: the details of
  /// each item and the query that listed the items.
  ///
  /// One level, not two: [other] and every element are sources of the same
  /// combination, [other] first, so "a source that failed with nothing to
  /// show wins" reads the same as in a record, and `retry()`, `refetch()` and
  /// `isFetching` cover all of them. A [CombinedResult] is deliberately not a
  /// source itself — nested, the rules would have to be read twice.
  ///
  /// One more source only. For more, put them in the list itself, typed by
  /// what they have in common —
  /// `<QueryResult<Object?>>[a, b, ...items].combine(...)` — and cast in the
  /// combiner.
  CombinedResult<R> combineWith<A, R>(
    QueryResult<A> other,
    R Function(List<T> values, A other) combiner, {
    CombineMemo<R>? memo,
    List<Object?>? keys,
  }) =>
      _combine(
          [other, ...this],
          () => combiner([for (final source in this) source.dataOrNull as T],
              other.dataOrNull as A),
          memo,
          keys);
}

// `dataOrNull as A`, not `!`: a nullable `A` holds nulls that are data.

/// [combine] over two results.
extension CombineQueryResults2<A, B> on (QueryResult<A>, QueryResult<B>) {
  /// What the two amount to together — see [CombinedResult] for the rules.
  /// [combiner] runs only when both have data. With a [memo] it must be a
  /// function of the sources and of [keys] alone — see [CombineMemo]; [keys]
  /// without a memo does nothing.
  CombinedResult<R> combine<R>(R Function(A a, B b) combiner,
          {CombineMemo<R>? memo, List<Object?>? keys}) =>
      _combine([$1, $2], () => combiner($1.dataOrNull as A, $2.dataOrNull as B),
          memo, keys);
}

/// [combine] over three results.
extension CombineQueryResults3<A, B, C> on (
  QueryResult<A>,
  QueryResult<B>,
  QueryResult<C>
) {
  /// What the three amount to together — see [CombinedResult] for the rules.
  CombinedResult<R> combine<R>(R Function(A a, B b, C c) combiner,
          {CombineMemo<R>? memo, List<Object?>? keys}) =>
      _combine(
          [$1, $2, $3],
          () => combiner(
              $1.dataOrNull as A, $2.dataOrNull as B, $3.dataOrNull as C),
          memo,
          keys);
}

/// [combine] over four results.
extension CombineQueryResults4<A, B, C, D> on (
  QueryResult<A>,
  QueryResult<B>,
  QueryResult<C>,
  QueryResult<D>
) {
  /// What the four amount to together — see [CombinedResult] for the rules.
  CombinedResult<R> combine<R>(R Function(A a, B b, C c, D d) combiner,
          {CombineMemo<R>? memo, List<Object?>? keys}) =>
      _combine(
          [$1, $2, $3, $4],
          () => combiner($1.dataOrNull as A, $2.dataOrNull as B,
              $3.dataOrNull as C, $4.dataOrNull as D),
          memo,
          keys);
}

/// [combine] over five results.
extension CombineQueryResults5<A, B, C, D, E> on (
  QueryResult<A>,
  QueryResult<B>,
  QueryResult<C>,
  QueryResult<D>,
  QueryResult<E>
) {
  /// What the five amount to together — see [CombinedResult] for the rules.
  CombinedResult<R> combine<R>(R Function(A a, B b, C c, D d, E e) combiner,
          {CombineMemo<R>? memo, List<Object?>? keys}) =>
      _combine(
          [$1, $2, $3, $4, $5],
          () => combiner($1.dataOrNull as A, $2.dataOrNull as B,
              $3.dataOrNull as C, $4.dataOrNull as D, $5.dataOrNull as E),
          memo,
          keys);
}

/// [combine] over six results. Past six, combine a list of what the sources
/// have in common — `<QueryResult<Object?>>[...]` at worst — and cast in the
/// combiner; a [CombinedResult] is not a source, so two combinations cannot
/// be combined.
extension CombineQueryResults6<A, B, C, D, E, F> on (
  QueryResult<A>,
  QueryResult<B>,
  QueryResult<C>,
  QueryResult<D>,
  QueryResult<E>,
  QueryResult<F>
) {
  /// What the six amount to together — see [CombinedResult] for the rules.
  CombinedResult<R> combine<R>(
          R Function(A a, B b, C c, D d, E e, F f) combiner,
          {CombineMemo<R>? memo,
          List<Object?>? keys}) =>
      _combine(
          [$1, $2, $3, $4, $5, $6],
          () => combiner(
              $1.dataOrNull as A,
              $2.dataOrNull as B,
              $3.dataOrNull as C,
              $4.dataOrNull as D,
              $5.dataOrNull as E,
              $6.dataOrNull as F),
          memo,
          keys);
}
