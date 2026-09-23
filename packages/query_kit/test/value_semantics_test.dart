/// Port-only: the value contract of every public value class, as tables.
///
/// An option field is written out in about nine places — constructor, field,
/// `toString`, `copyWith`, each subclass, the `Defaulted*` class's `==` and
/// `hashCode`, the client's defaulting, `withSelect` — and a place that is
/// missed is a silent bug: a field lost in a `copyWith`, or a rebuild that
/// never happens because `==` does not see it. These tables set every field
/// to a non-default value and then change one field at a time, so a field
/// forgotten in any one of those places fails here by name.
library;

import 'dart:async';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

// Top-level functions, because a tear-off of one compares equal to another
// tear-off of it — which is what lets two separately built values be equal.
int queryFnA(QueryFunctionContext context) => 1;
int queryFnB(QueryFunctionContext context) => 2;
int pageFnA(InfinitePageContext<int> context) => 1;
int pageFnB(InfinitePageContext<int> context) => 2;
int? nextParamA(int page, List<int> pages, int param, List<int> params) => 1;
int? nextParamB(int page, List<int> pages, int param, List<int> params) => 2;
T shareA<T>(T? previous, T next) => next;
T shareB<T>(T? previous, T next) => next;
DateTime? updatedAtA() => DateTime(2001);
DateTime? updatedAtB() => DateTime(2002);
bool enabledWhenA(Query<Object?> query) => true;
bool enabledWhenB(Query<Object?> query) => false;
StaleTime staleA(Query<Object?> query) => StaleTime.zero;
StaleTime staleB(Query<Object?> query) => StaleTime.infinite;
bool retryA(int count, Object error, StackTrace stackTrace) => true;
bool retryB(int count, Object error, StackTrace stackTrace) => false;
Duration delayA(int count, Object error) => Duration.zero;
Duration delayB(int count, Object error) => Duration.zero;
RefetchOn refetchOnA(Query<Object?> query) => RefetchOn.never;
RefetchOn refetchOnB(Query<Object?> query) => RefetchOn.always;
Duration? intervalA(Query<Object?> query) => null;
Duration? intervalB(Query<Object?> query) => null;
int? seedA() => 1;
int? seedB() => 2;
int? placeholderA(int? previous, Query<int>? query) => 1;
int? placeholderB(int? previous, Query<int>? query) => 2;
int selectA(int data) => data;
int selectB(int data) => -data;
String selectPagesA(InfiniteData<int, int> data) => 'a';
String selectPagesB(InfiniteData<int, int> data) => 'b';
Future<int> mutationFnA(int variables) async => 1;
Future<int> mutationFnB(int variables) async => 2;
Future<int> mutationFnWithContextA(
        int variables, MutationFunctionContext<String> context) async =>
    1;
Future<int> mutationFnWithContextB(
        int variables, MutationFunctionContext<String> context) async =>
    2;
Object? erasedQueryFnA(QueryFunctionContext context) => 1;
Object? erasedQueryFnB(QueryFunctionContext context) => 2;
Object? erasedShareA(Object? previous, Object? next) => next;
Object? erasedShareB(Object? previous, Object? next) => next;
Object? erasedMutationFnA(Object? variables) => 1;
Object? erasedMutationFnB(Object? variables) => 2;
String? onMutateA(int variables) => 'a';
String? onMutateB(int variables) => 'b';
void onSuccessA(int data, int variables, String? context) {}
void onSuccessB(int data, int variables, String? context) {}
void onErrorA(Object e, StackTrace s, int variables, String? context) {}
void onErrorB(Object e, StackTrace s, int variables, String? context) {}
void onSettledA(int? d, Object? e, StackTrace? s, int v, String? c) {}
void onSettledB(int? d, Object? e, StackTrace? s, int v, String? c) {}
Future<QueryResult<int>> refetchA({bool cancelRefetch = true}) =>
    throw UnimplementedError();
void mutateA(int variables) {}
Future<int> mutateAsyncA(int variables) async => 0;
void resetA() {}

/// `a` when [field] is not the one being varied, `b` when it is.
T pick<T>(String field, String? vary, T a, T b) => field == vary ? b : a;

/// Asserts the value contract over a base and one variant per field: equal
/// inputs are equal and hash alike, and each field alone breaks both.
void valueTable<T extends Object>(
  String name,
  List<String> fields,
  T Function({String? vary}) build, {
  bool hasToString = true,
}) {
  group('$name value equality', () {
    test('two instances built from equal inputs are equal and hash alike', () {
      final a = build();
      final b = build();
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      if (hasToString) {
        expect(a.toString(), isNot(startsWith('Instance of')));
      }
    });
    for (final field in fields) {
      test('$field takes part in == and hashCode', () {
        final base = build();
        final changed = build(vary: field);
        expect(changed == base, isFalse);
        expect(base == changed, isFalse);
        expect(changed.hashCode, isNot(base.hashCode));
      });
    }
  });
}

/// One option field: its name, how to read it, the value the base holds,
/// and a copy with that one field changed.
typedef Field<O> = ({
  String name,
  Object? Function(O options) read,
  Object? expected,
  O Function(O options) change,
});

Field<O> field<O>(
  String name,
  Object? Function(O options) read,
  Object? expected,
  O Function(O options) change,
) =>
    (name: name, read: read, expected: expected, change: change);

/// The two seed timestamps clear each other in `copyWith`, on purpose; every
/// other field must leave the rest alone.
const _coupled = {'initialDataUpdatedAt', 'initialDataUpdatedAtCompute'};

/// Asserts the constructor stores every field, `copyWith()` keeps every
/// field, and `copyWith(field: …)` changes that field alone.
void copyWithTable<O>(String name, O base, List<Field<O>> fields,
    O Function(O options) copyNothing) {
  group('$name copyWith', () {
    test('the constructor stores every field', () {
      for (final f in fields) {
        expect(f.read(base), f.expected, reason: f.name);
      }
    });
    test('copyWith() with no arguments keeps every field', () {
      final copy = copyNothing(base);
      expect(copy.runtimeType, base.runtimeType);
      for (final f in fields) {
        expect(f.read(copy), f.expected, reason: f.name);
      }
    });
    for (final changed in fields) {
      test('copyWith(${changed.name}: …) changes ${changed.name} alone', () {
        final copy = changed.change(base);
        expect(copy.runtimeType, base.runtimeType);
        expect(changed.read(copy), isNot(changed.expected));
        for (final other in fields) {
          if (identical(other, changed)) continue;
          if (_coupled.contains(changed.name) &&
              _coupled.contains(other.name)) {
            continue;
          }
          expect(other.read(copy), other.expected,
              reason: '${other.name} after changing ${changed.name}');
        }
      });
    }
  });
}

final _keyA = QueryKey(const ['a']);
final _keyB = QueryKey(const ['b']);
final _dateA = DateTime(2020);
final _dateB = DateTime(2021);
InfiniteData<int, int> _pages(int page) =>
    InfiniteData(pages: [page], pageParams: [0]);

void main() {
  group('sealed option values', () {
    // Each list holds values that are pairwise unequal; each entry is built
    // twice, without `const`, so equality is not identity.
    final groups = <String, List<Object Function()>>{
      'StaleTime': [
        () => StaleTime.duration(Duration(seconds: _one)),
        () => StaleTime.duration(Duration(seconds: _one + 1)),
        StaleTimeStatic.new,
        StaleTimeInfinite.new,
        () => StaleTime.dynamic(staleA),
        () => StaleTime.dynamic(staleB),
      ],
      'GcTime': [
        () => GcTime.duration(Duration(seconds: _one)),
        () => GcTime.duration(Duration(seconds: _one + 1)),
        GcTimeNever.new,
      ],
      'Enabled': [
        EnabledYes.new,
        EnabledNo.new,
        () => Enabled.when(enabledWhenA),
        () => Enabled.when(enabledWhenB),
      ],
      'RetryPolicy': [
        RetryNever.new,
        RetryAlways.new,
        () => RetryPolicy.times(_one),
        () => RetryPolicy.times(_one + 1),
        () => RetryPolicy.when(retryA),
        () => RetryPolicy.when(retryB),
      ],
      'RetryDelay': [
        () => RetryDelay.fixed(Duration(seconds: _one)),
        () => RetryDelay.fixed(Duration(seconds: _one + 1)),
        RetryDelay.exponential,
        () => RetryDelay.exponential(base: Duration(seconds: _one + 1)),
        () => RetryDelay.exponential(maximum: Duration(seconds: _one)),
        () => RetryDelay.dynamic(delayA),
        () => RetryDelay.dynamic(delayB),
      ],
      'RefetchOn': [
        RefetchOnNever.new,
        RefetchOnIfStale.new,
        RefetchOnAlways.new,
        () => RefetchOn.when(refetchOnA),
        () => RefetchOn.when(refetchOnB),
      ],
      'RefetchInterval': [
        RefetchIntervalOff.new,
        () => RefetchInterval.every(Duration(seconds: _one)),
        () => RefetchInterval.every(Duration(seconds: _one + 1)),
        () => RefetchInterval.dynamic(intervalA),
        () => RefetchInterval.dynamic(intervalB),
      ],
      'InitialData': [
        () => InitialData<int>.value(_one),
        () => InitialData<int>.value(_one + 1),
        () => InitialData<num>.value(_one),
        () => InitialData<int>.compute(seedA),
        () => InitialData<int>.compute(seedB),
      ],
      'PlaceholderData': [
        PlaceholderData<int>.keepPrevious,
        PlaceholderData<num>.keepPrevious,
        () => PlaceholderData<int>.value(_one),
        () => PlaceholderData<int>.value(_one + 1),
        () => PlaceholderData<int>.compute(placeholderA),
        () => PlaceholderData<int>.compute(placeholderB),
      ],
      'MutationScope': [
        () => MutationScope('a$_one'),
        () => MutationScope('b$_one'),
      ],
      'FetchMore': [
        () => FetchMore(FetchDirection.forward),
        () => FetchMore(FetchDirection.backward),
      ],
      'InfiniteData': [
        () => InfiniteData<int, int>(pages: [_one], pageParams: [0]),
        () => InfiniteData<int, int>(pages: [_one + 1], pageParams: [0]),
        () => InfiniteData<int, int>(pages: [_one], pageParams: [1]),
        () => InfiniteData<num, int>(pages: [_one], pageParams: [0]),
      ],
      'QueryKey': [
        () => QueryKey([
              {'b', 'a'}
            ]),
        () => QueryKey([
              {'a', 'c'}
            ]),
        () => QueryKey([
              {'a': 1}
            ]),
      ],
    };
    for (final MapEntry(key: name, value: builders) in groups.entries) {
      test('$name: equal values are equal and hash alike; distinct differ', () {
        for (var i = 0; i < builders.length; i++) {
          final a = builders[i]();
          final again = builders[i]();
          expect(a, again, reason: '$name #$i');
          expect(a.hashCode, again.hashCode, reason: '$name #$i');
          expect(a.toString(), isNot(startsWith('Instance of')));
          for (var j = 0; j < builders.length; j++) {
            if (i == j) continue;
            final b = builders[j]();
            expect(a == b, isFalse, reason: '$name #$i vs #$j');
          }
        }
      });
    }

    test('a Set in a QueryKey hashes and matches in any iteration order', () {
      final a = QueryKey([
        'todos',
        {3, 1, 2}
      ]);
      final b = QueryKey([
        'todos',
        {1, 2, 3}
      ]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), b.toString());
    });

    test('InfiniteData.isEmpty', () {
      expect(InfiniteData<int, int>(pages: [], pageParams: []).isEmpty, isTrue);
      expect(_pages(1).isEmpty, isFalse);
    });

    test('CancelledError.toString names both flags', () {
      expect(const CancelledError(revert: true).toString(),
          'CancelledError(revert: true, silent: false)');
    });
  });

  group('resolving option values against a query', () {
    late QueryClient client;
    late Query<int> query;
    setUp(() {
      client = testClient();
      query = client.queryCache.build<int>(client,
          client.defaultQueryOptions(QueryOptions<int>(queryKey: _keyA)));
    });
    tearDown(() => client.clear());

    test('StaleTime.resolve peels dynamic layers down to a duration or null',
        () {
      expect(StaleTime.zero.resolve(query), Duration.zero);
      expect(StaleTime.static.resolve(query), isNull);
      expect(StaleTime.infinite.resolve(query), isNull);
      expect(
          StaleTime.dynamic((_) => const StaleTime.dynamic(staleA))
              .resolve(query),
          Duration.zero);
      expect(const StaleTime.dynamic(staleB).resolve(query), isNull);
    });

    test('Enabled, RefetchOn and RefetchInterval resolve every variant', () {
      expect(Enabled.yes.resolve(query), isTrue);
      expect(Enabled.no.resolve(query), isFalse);
      expect(const Enabled.when(enabledWhenB).resolve(query), isFalse);
      expect(
          RefetchOn.when((_) => const RefetchOn.when(refetchOnB))
              .resolve(query),
          RefetchOn.always);
      expect(RefetchInterval.off.resolve(query), isNull);
      expect(const RefetchInterval.every(Duration(seconds: 3)).resolve(query),
          const Duration(seconds: 3));
      expect(
          RefetchInterval.dynamic((_) => const Duration(seconds: 4))
              .resolve(query),
          const Duration(seconds: 4));
    });
  });

  group('QueryCancelToken', () {
    testFakeAsync(
        'whenCancelled completes and throwIfCancelled throws once '
        'the query is cancelled', (time) async {
      final client = testClient();
      final key = queryKey();
      var whenCancelledRan = false;
      Object? thrown;
      final fetch = client.query(QueryOptions<int>(
        queryKey: key,
        queryFn: (context) async {
          final signal = context.signal;
          signal.throwIfCancelled();
          unawaited(signal.whenCancelled.then((_) => whenCancelledRan = true));
          await sleep(ms(10));
          try {
            signal.throwIfCancelled();
          } catch (error) {
            thrown = error;
          }
          return 1;
        },
      ));
      fetch.ignore();
      await time.advance(ms(1));
      expect(whenCancelledRan, isFalse);
      await client.cancelQueries(filters: QueryFilters(queryKey: key));
      await time.flushMicrotasks();
      expect(whenCancelledRan, isTrue);
      await time.advance(ms(10));
      expect(thrown, isA<CancelledError>());
      client.clear();
    });
  });

  valueTable<QueryDefaults>(
    'QueryDefaults',
    const [
      'queryFn',
      'structuralSharing',
      'enabled',
      'staleTime',
      'gcTime',
      'retry',
      'retryDelay',
      'retryOnMount',
      'networkMode',
      'refetchOnMount',
      'refetchOnWindowFocus',
      'refetchOnReconnect',
      'refetchInterval',
      'refetchIntervalInBackground',
      'meta',
    ],
    _queryDefaults,

    // No toString of its own: a plain configuration holder.
    hasToString: false,
  );

  group('QueryDefaults.mergedWith', () {
    test('a null or empty overlay changes nothing', () {
      final base = _queryDefaults();
      expect(identical(base.mergedWith(null), base), isTrue);
      expect(base.mergedWith(const QueryDefaults()), base);
      expect(const QueryDefaults().mergedWith(base), base);
    });
    for (final name in _queryDefaultFields) {
      test('an overlay setting only $name wins for $name alone', () {
        final merged = _queryDefaults()
            .mergedWith(_queryDefaults(vary: name, sparse: true));
        expect(merged, _queryDefaults(vary: name));
      });
    }
  });

  valueTable<MutationDefaults>(
    'MutationDefaults',
    _mutationDefaultFields,
    _mutationDefaults,

    // No toString of its own: a plain configuration holder.
    hasToString: false,
  );

  group('MutationDefaults.mergedWith', () {
    test('a null or empty overlay changes nothing', () {
      final base = _mutationDefaults();
      expect(identical(base.mergedWith(null), base), isTrue);
      expect(base.mergedWith(const MutationDefaults()), base);
    });
    for (final name in _mutationDefaultFields) {
      test('an overlay setting only $name wins for $name alone', () {
        final merged = _mutationDefaults()
            .mergedWith(_mutationDefaults(vary: name, sparse: true));
        expect(merged, _mutationDefaults(vary: name));
      });
    }
  });

  valueTable<DefaultOptions>(
    'DefaultOptions',
    const ['queries', 'mutations'],
    ({vary}) => DefaultOptions(
      queries: _queryDefaults(vary: vary == 'queries' ? 'meta' : null),
      mutations: _mutationDefaults(vary: vary == 'mutations' ? 'meta' : null),
    ),
    hasToString: false,
  );

  valueTable<QueryState<int>>(
    'QueryState',
    const [
      'hasData',
      'data',
      'dataUpdateCount',
      'dataUpdatedAt',
      'error',
      'errorUpdateCount',
      'consecutiveErrorCount',
      'errorUpdatedAt',
      'fetchFailureCount',
      'fetchFailureReason',
      'fetchMeta',
      'isInvalidated',
      'status',
      'fetchStatus',
    ],
    _queryState,
  );

  group('QueryState', () {
    test('copyWith() keeps every field, stack traces included', () {
      final base = _queryState();
      final copy = base.copyWith();
      expect(copy, base);
      expect(copy.errorStackTrace, same(base.errorStackTrace));
      expect(copy.fetchFailureStackTrace, same(base.fetchFailureStackTrace));
    });

    // A StackTrace compares by identity, so two failures with the same error
    // would never be equal if it counted; the traces ride along unexamined.
    test('the stack traces take no part in ==', () {
      expect(_queryState(vary: 'errorStackTrace'), _queryState());
      expect(_queryState(vary: 'fetchFailureStackTrace'), _queryState());
    });

    test('the clear flags clear what they name and nothing else', () {
      final base = _queryState();
      final noData = base.copyWith(clearData: true);
      expect((noData.hasData, noData.data), (false, null));
      final noError = base.copyWith(clearError: true);
      expect((noError.error, noError.errorStackTrace), (null, null));
      expect(noError.errorUpdatedAt, base.errorUpdatedAt);
      final noFailure = base.copyWith(clearFetchFailure: true);
      expect((
        noFailure.fetchFailureCount,
        noFailure.fetchFailureReason,
        noFailure.fetchFailureStackTrace
      ), (
        0,
        null,
        null
      ));
      expect(base.copyWith(clearFetchMeta: true).fetchMeta, isNull);
    });

    test('isFetched is true once data or an error has been written', () {
      expect(const QueryState<int>().isFetched, isFalse);
      expect(const QueryState<int>(dataUpdateCount: 1).isFetched, isTrue);
      expect(const QueryState<int>(errorUpdateCount: 1).isFetched, isTrue);
    });

    test('toString shows status, data and error', () {
      expect(
          _queryState().toString(),
          allOf(contains('QueryState('), contains('data: 1'),
              contains('error: boom'), contains('invalidated: true')));
    });
  });

  for (final variant in ['pending', 'success', 'error']) {
    valueTable<QueryResult<int>>(
      'QueryResult ($variant)',
      [
        'fetchStatus',
        'dataUpdatedAt',
        'errorUpdatedAt',
        'failureCount',
        'failureReason',
        'errorUpdateCount',
        'consecutiveErrorCount',
        'isStale',
        'isEnabled',
        'isFetched',
        'isFetchedAfterMount',
        'isPlaceholderData',
        if (variant != 'pending') 'data',
        if (variant == 'error') ...['error', 'hasStaleData'],
      ],
      ({vary}) => _queryResult(variant, vary: vary),
    );
  }

  test('QueryResult variants never equal each other', () {
    final results = [
      for (final v in ['pending', 'success', 'error']) _queryResult(v)
    ];
    for (final a in results) {
      for (final b in results) {
        if (!identical(a, b)) expect(a == b, isFalse, reason: '$a vs $b');
      }
    }
    expect(results[0].toString(), contains('QueryPending'));
    expect(results[2].toString(), contains('hasStaleData: true'));
  });

  for (final variant in ['idle', 'pending', 'success', 'error']) {
    valueTable<MutationResult<int, int>>(
      'MutationResult ($variant)',
      [
        'variables',
        'hasVariables',
        'failureCount',
        'failureReason',
        'isPaused',
        'submittedAt',
        if (variant == 'success') 'data',
        if (variant == 'error') 'error',
      ],
      ({vary}) => _mutationResult(variant, vary: vary),
    );
  }

  test('MutationResult toString shows variables, outcome and pause', () {
    expect(_mutationResult('success').toString(),
        'MutationSuccess<int, int>(variables: 1, data: 1, paused)');
    expect(_mutationResult('error').toString(),
        'MutationError<int, int>(variables: 1, error: boom, paused)');
    expect(_mutationResult('pending', vary: 'hasVariables').toString(),
        'MutationPending<int, int>(paused)');
  });

  group('CombinedResult', () {
    CombinedResult<int> combine(QueryResult<int> a, QueryResult<int> b) =>
        (a, b).combine((x, y) => x + y);

    test('every variant has value equality and a readable toString', () {
      final pending = combine(_queryResult('pending'), _queryResult('success'));
      final error = combine(
          _queryResult('error', vary: 'hasStaleData'), _queryResult('success'));
      final data = combine(_queryResult('success'), _queryResult('success'));
      for (final (value, again, text) in [
        (
          pending,
          combine(_queryResult('pending'), _queryResult('success')),
          'CombinedPending<int>(isFetching: true)'
        ),
        (
          error,
          combine(_queryResult('error', vary: 'hasStaleData'),
              _queryResult('success')),
          'CombinedError<int>(boom, isFetching: true)'
        ),
        (
          data,
          combine(_queryResult('success'), _queryResult('success')),
          'CombinedData<int>(2, isFetching: true, refetchError: null)'
        ),
      ]) {
        expect(value, again);
        expect(value.hashCode, again.hashCode);
        expect(value.toString(), text);
      }
      expect(pending == error, isFalse);
      expect(error == data, isFalse);
      expect(data.hasData, isTrue);
      expect(pending.hasData, isFalse);
      expect(
          combine(_queryResult('success', vary: 'data'),
                  _queryResult('success'))
              .hashCode,
          isNot(data.hashCode));
    });

    // CombinedData's == reads five things besides its data; each alone must
    // break it, or a `buildWhen` misses the change.
    test('each flag CombinedData compares takes part in == and hashCode', () {
      final base = combine(_queryResult('success'), _queryResult('success'));
      final variants = <String, CombinedResult<int>>{
        'isFetching': combine(_queryResult('success', vary: 'fetchStatus'),
            _queryResult('success', vary: 'fetchStatus')),
        'isPaused': combine(
            _queryResult('success', vary: 'paused'), _queryResult('success')),
        'isPlaceholderData': combine(
            _queryResult('success', vary: 'isPlaceholderData'),
            _queryResult('success', vary: 'isPlaceholderData')),
        'isStale': combine(_queryResult('success', vary: 'isStale'),
            _queryResult('success', vary: 'isStale')),
      };
      expect(base.isFetching, isTrue);
      expect((base as CombinedData<int>).isStale, isTrue);
      expect(base.isPlaceholderData, isTrue);
      for (final MapEntry(key: name, value: changed) in variants.entries) {
        expect(changed, isA<CombinedData<int>>(), reason: name);
        expect(changed == base, isFalse, reason: name);
        expect(changed.hashCode, isNot(base.hashCode), reason: name);
      }
      final refetchError =
          combine(_queryResult('error'), _queryResult('success'));
      final otherRefetchError = combine(
          _queryResult('error', vary: 'error'), _queryResult('success'));
      expect(refetchError, isA<CombinedData<int>>());
      expect((refetchError as CombinedData<int>).refetchError, 'boom');
      expect(refetchError.dataOrNull, otherRefetchError.dataOrNull);
      expect(refetchError == otherRefetchError, isFalse);
      expect(refetchError.hashCode, isNot(otherRefetchError.hashCode));
    });
  });

  // Options without value equality: the constructor stores, copyWith keeps,
  // and the client's defaulting sees every field.
  final plain = QueryObserverOptions<int>(
    queryKey: _keyA,
    queryFn: queryFnA,
    enabled: Enabled.no,
    staleTime: StaleTime.infinite,
    gcTime: GcTime.never,
    retry: RetryPolicy.always,
    retryDelay: const RetryDelay.fixed(Duration(seconds: 1)),
    networkMode: NetworkMode.always,
    initialData: const InitialData.value(1),
    initialDataUpdatedAt: _dateA,
    structuralSharing: shareA<int>,
    meta: 'metaA',
    placeholderData: const PlaceholderData.value(1),
    refetchOnMount: RefetchOn.always,
    refetchOnWindowFocus: RefetchOn.always,
    refetchOnReconnect: RefetchOn.always,
    refetchInterval: const RefetchInterval.every(Duration(seconds: 1)),
    refetchIntervalInBackground: true,
    retryOnMount: false,
  );
  final selecting = plain.withSelect(selectA);
  final cacheLayer = QueryOptions<int>(
    queryKey: _keyA,
    queryFn: queryFnA,
    enabled: Enabled.no,
    staleTime: StaleTime.infinite,
    gcTime: GcTime.never,
    retry: RetryPolicy.always,
    retryDelay: const RetryDelay.fixed(Duration(seconds: 1)),
    networkMode: NetworkMode.always,
    initialData: const InitialData.value(1),
    initialDataUpdatedAt: _dateA,
    structuralSharing: shareA<int>,
    meta: 'metaA',
  );

  copyWithTable<QueryOptions<int>>(
    'QueryOptions',
    cacheLayer,
    [
      ..._queryOptionsFields<QueryOptions<int>, int>(
        (o, c) => o.copyWith(
          queryKey: c.queryKey,
          queryFn: c.queryFn,
          enabled: c.enabled,
          staleTime: c.staleTime,
          gcTime: c.gcTime,
          retry: c.retry,
          retryDelay: c.retryDelay,
          networkMode: c.networkMode,
          initialData: c.initialData,
          initialDataUpdatedAt: c.initialDataUpdatedAt,
          initialDataUpdatedAtCompute: c.initialDataUpdatedAtCompute,
          structuralSharing: c.structuralSharing,
          meta: c.meta,
        ),
        initialDataA: const InitialData.value(1),
        initialDataB: const InitialData.value(2),
      ),
      field('queryFn', (o) => o.queryFn, queryFnA,
          (o) => o.copyWith(queryFn: queryFnB)),
    ],
    (o) => o.copyWith(),
  );

  for (final (name, base) in [
    ('QueryObserverOptions', plain as QueryObserverOptionsBase<int, int>),
    ('QuerySelectOptions', selecting),
  ]) {
    copyWithTable<QueryObserverOptionsBase<int, int>>(
      name,
      base,
      [
        ..._queryOptionsFields<QueryObserverOptionsBase<int, int>, int>(
          (o, c) => o.copyWith(
            queryKey: c.queryKey,
            queryFn: c.queryFn,
            enabled: c.enabled,
            staleTime: c.staleTime,
            gcTime: c.gcTime,
            retry: c.retry,
            retryDelay: c.retryDelay,
            networkMode: c.networkMode,
            initialData: c.initialData,
            initialDataUpdatedAt: c.initialDataUpdatedAt,
            initialDataUpdatedAtCompute: c.initialDataUpdatedAtCompute,
            structuralSharing: c.structuralSharing,
            meta: c.meta,
          ),
          initialDataA: const InitialData.value(1),
          initialDataB: const InitialData.value(2),
        ),
        field('queryFn', (o) => o.queryFn, queryFnA,
            (o) => o.copyWith(queryFn: queryFnB)),
        ..._observerFields<QueryObserverOptionsBase<int, int>>(
          read: (o) => (
            o.placeholderData,
            o.refetchOnMount,
            o.refetchOnWindowFocus,
            o.refetchOnReconnect,
            o.refetchInterval,
            o.refetchIntervalInBackground,
            o.retryOnMount,
          ),
          change: (o, c) => o.copyWith(
            placeholderData: c.placeholderData as PlaceholderData<int>?,
            refetchOnMount: c.refetchOnMount,
            refetchOnWindowFocus: c.refetchOnWindowFocus,
            refetchOnReconnect: c.refetchOnReconnect,
            refetchInterval: c.refetchInterval,
            refetchIntervalInBackground: c.refetchIntervalInBackground,
            retryOnMount: c.retryOnMount,
          ),
          placeholderA: const PlaceholderData<int>.value(1),
          placeholderB: const PlaceholderData<int>.value(2),
        ),
        if (base is QuerySelectOptions<int, int>)
          field(
              'select',
              (o) => o.select,
              selectA,
              (o) => (o as QuerySelectOptions<int, int>)
                  .copyWith(select: selectB)),
      ],
      (o) => o.copyWith(),
    );
  }

  // `behavior` is the one field no table varies: it is `@internal` in the
  // constructors and absent from every `copyWith`, so a copy must carry it
  // over untouched — a lost one would turn an infinite query into a plain
  // one — and the defaulted options must compare it.
  test('every plain shape carries behavior through copyWith and withSelect',
      () {
    final behavior = _Behavior();
    final shapes = <QueryOptions<int>>[
      QueryOptions<int>(queryKey: _keyA, behavior: behavior),
      QueryObserverOptions<int>(queryKey: _keyA, behavior: behavior),
      QueryObserverOptions<int>(queryKey: _keyA, behavior: behavior)
          .withSelect(selectA),
    ];
    for (final options in shapes) {
      final type = options.runtimeType;
      expect(options.behavior, same(behavior), reason: '$type');
      expect(options.copyWith().behavior, same(behavior), reason: '$type');
      expect(options.copyWith(meta: 'm').behavior, same(behavior),
          reason: '$type');
    }
    final client = testClient();
    expect(
        client.defaultQueryOptions(shapes.first) ==
            client.defaultQueryOptions(
                QueryOptions<int>(queryKey: _keyA, behavior: _Behavior())),
        isFalse);
    expect(
        client
            .defaultQueryObserverOptions<int, int>(
                shapes[1] as QueryObserverOptions<int>)
            .behavior,
        same(behavior));
    client.clear();
  });

  test('QuerySelectOptions.copyWith(select: …) replaces the projection', () {
    final copy = selecting.copyWith(select: selectB);
    expect(copy.select, selectB);
    expect(plain.select, isNull);
    expect(plain.copyWith().select, isNull);
  });

  test('toString lists every set field by name', () {
    for (final options in <QueryOptions<int>>[cacheLayer, plain, selecting]) {
      final text = options.toString();
      for (final name in [
        'queryFn',
        'enabled',
        'staleTime',
        'gcTime',
        'retry',
        'retryDelay',
        'networkMode',
        'initialData',
        'initialDataUpdatedAt',
        'structuralSharing',
        'meta',
      ]) {
        expect(text, contains('$name: '), reason: '$name in $text');
      }
    }
    for (final name in [
      'placeholderData',
      'refetchOnMount',
      'refetchOnWindowFocus',
      'refetchOnReconnect',
      'refetchInterval',
      'refetchIntervalInBackground',
      'retryOnMount',
    ]) {
      expect(plain.toString(), contains('$name: '));
    }
    expect(selecting.toString(), contains('select: '));
  });

  // The infinite shapes.
  final infinite = InfiniteQueryObserverOptions<int, int>(
    queryKey: _keyA,
    pageFn: pageFnA,
    initialPageParam: 1,
    getNextPageParam: nextParamA,
    getPreviousPageParam: nextParamA,
    maxPages: 3,
    enabled: Enabled.no,
    staleTime: StaleTime.infinite,
    gcTime: GcTime.never,
    retry: RetryPolicy.always,
    retryDelay: const RetryDelay.fixed(Duration(seconds: 1)),
    networkMode: NetworkMode.always,
    initialData: InitialData.value(_pages(1)),
    initialDataUpdatedAt: _dateA,
    structuralSharing: shareA<InfiniteData<int, int>>,
    meta: 'metaA',
    placeholderData: const PlaceholderData.keepPrevious(),
    refetchOnMount: RefetchOn.always,
    refetchOnWindowFocus: RefetchOn.always,
    refetchOnReconnect: RefetchOn.always,
    refetchInterval: const RefetchInterval.every(Duration(seconds: 1)),
    refetchIntervalInBackground: true,
    retryOnMount: false,
  );
  final infiniteSelecting = infinite.withSelect(selectPagesA);
  final infiniteCacheLayer = InfiniteQueryOptions<int, int>(
    queryKey: _keyA,
    pageFn: pageFnA,
    initialPageParam: 1,
    getNextPageParam: nextParamA,
    getPreviousPageParam: nextParamA,
    maxPages: 3,
    pages: 2,
    enabled: Enabled.no,
    staleTime: StaleTime.infinite,
    gcTime: GcTime.never,
    retry: RetryPolicy.always,
    retryDelay: const RetryDelay.fixed(Duration(seconds: 1)),
    networkMode: NetworkMode.always,
    initialData: InitialData.value(_pages(1)),
    initialDataUpdatedAt: _dateA,
    structuralSharing: shareA<InfiniteData<int, int>>,
    meta: 'metaA',
  );

  List<Field<O>> pagingFields<O extends InfiniteQueryOptions<int, int>>(
    O Function(
      O o, {
      InfinitePageFn<int, int>? pageFn,
      int? initialPageParam,
      PageParamFn<int, int>? getNextPageParam,
      PageParamFn<int, int>? getPreviousPageParam,
      int? maxPages,
    }) copy,
  ) =>
      [
        field('pageFn', (o) => o.pageFn, pageFnA,
            (o) => copy(o, pageFn: pageFnB)),
        field('initialPageParam', (o) => o.initialPageParam, 1,
            (o) => copy(o, initialPageParam: 2)),
        field('getNextPageParam', (o) => o.getNextPageParam, nextParamA,
            (o) => copy(o, getNextPageParam: nextParamB)),
        field('getPreviousPageParam', (o) => o.getPreviousPageParam, nextParamA,
            (o) => copy(o, getPreviousPageParam: nextParamB)),
        field('maxPages', (o) => o.maxPages, 3, (o) => copy(o, maxPages: 4)),
      ];

  copyWithTable<InfiniteQueryOptions<int, int>>(
    'InfiniteQueryOptions',
    infiniteCacheLayer,
    [
      ..._queryOptionsFields<InfiniteQueryOptions<int, int>,
          InfiniteData<int, int>>(
        (o, c) => o.copyWith(
          queryKey: c.queryKey,
          enabled: c.enabled,
          staleTime: c.staleTime,
          gcTime: c.gcTime,
          retry: c.retry,
          retryDelay: c.retryDelay,
          networkMode: c.networkMode,
          initialData: c.initialData,
          initialDataUpdatedAt: c.initialDataUpdatedAt,
          initialDataUpdatedAtCompute: c.initialDataUpdatedAtCompute,
          structuralSharing: c.structuralSharing,
          meta: c.meta,
        ),
        initialDataA: InitialData.value(_pages(1)),
        initialDataB: InitialData.value(_pages(2)),
      ),
      ...pagingFields<InfiniteQueryOptions<int, int>>((o,
              {pageFn,
              initialPageParam,
              getNextPageParam,
              getPreviousPageParam,
              maxPages}) =>
          o.copyWith(
            pageFn: pageFn,
            initialPageParam: initialPageParam,
            getNextPageParam: getNextPageParam,
            getPreviousPageParam: getPreviousPageParam,
            maxPages: maxPages,
          )),
      field('pages', (o) => o.pages, 2, (o) => o.copyWith(pages: 5)),
    ],
    (o) => o.copyWith(),
  );

  for (final (name, base) in [
    (
      'InfiniteQueryObserverOptions',
      infinite as InfiniteQueryObserverOptionsBase<int, int, Object?>
    ),
    ('InfiniteQuerySelectOptions', infiniteSelecting),
  ]) {
    copyWithTable<InfiniteQueryObserverOptionsBase<int, int, Object?>>(
      name,
      base,
      [
        ..._queryOptionsFields<
            InfiniteQueryObserverOptionsBase<int, int, Object?>,
            InfiniteData<int, int>>(
          (o, c) => o.copyWith(
            queryKey: c.queryKey,
            enabled: c.enabled,
            staleTime: c.staleTime,
            gcTime: c.gcTime,
            retry: c.retry,
            retryDelay: c.retryDelay,
            networkMode: c.networkMode,
            initialData: c.initialData,
            initialDataUpdatedAt: c.initialDataUpdatedAt,
            initialDataUpdatedAtCompute: c.initialDataUpdatedAtCompute,
            structuralSharing: c.structuralSharing,
            meta: c.meta,
          ),
          initialDataA: InitialData.value(_pages(1)),
          initialDataB: InitialData.value(_pages(2)),
        ),
        ...pagingFields<InfiniteQueryObserverOptionsBase<int, int, Object?>>((o,
                {pageFn,
                initialPageParam,
                getNextPageParam,
                getPreviousPageParam,
                maxPages}) =>
            o.copyWith(
              pageFn: pageFn,
              initialPageParam: initialPageParam,
              getNextPageParam: getNextPageParam,
              getPreviousPageParam: getPreviousPageParam,
              maxPages: maxPages,
            )),
        ..._observerFields<InfiniteQueryObserverOptionsBase<int, int, Object?>>(
          read: (o) => (
            o.placeholderData,
            o.refetchOnMount,
            o.refetchOnWindowFocus,
            o.refetchOnReconnect,
            o.refetchInterval,
            o.refetchIntervalInBackground,
            o.retryOnMount,
          ),
          change: (o, c) => o.copyWith(
            placeholderData:
                c.placeholderData as PlaceholderData<InfiniteData<int, int>>?,
            refetchOnMount: c.refetchOnMount,
            refetchOnWindowFocus: c.refetchOnWindowFocus,
            refetchOnReconnect: c.refetchOnReconnect,
            refetchInterval: c.refetchInterval,
            refetchIntervalInBackground: c.refetchIntervalInBackground,
            retryOnMount: c.retryOnMount,
          ),
          placeholderA:
              const PlaceholderData<InfiniteData<int, int>>.keepPrevious(),
          placeholderB:
              PlaceholderData<InfiniteData<int, int>>.value(_pages(9)),
        ),
      ],
      (o) => o.copyWith(),
    );
  }

  group('infinite copyWith guards', () {
    test('every infinite shape refuses a queryFn', () {
      for (final options in <InfiniteQueryOptions<int, int>>[
        infiniteCacheLayer,
        infinite,
        infiniteSelecting,
      ]) {
        expect(
            () => options.copyWith(
                queryFn: (_) => throw StateError('never called')),
            throwsArgumentError,
            reason: '${options.runtimeType}');
      }
    });

    test('an observer shape refuses pages; select replaces the projection', () {
      expect(() => infinite.copyWith(pages: 2), throwsArgumentError);
      expect(() => infiniteSelecting.copyWith(pages: 2), throwsArgumentError);
      expect(infiniteSelecting.copyWith(select: selectPagesB).select,
          selectPagesB);
      expect(infiniteSelecting.copyWith().select, selectPagesA);
    });

    test('toString lists the paging fields', () {
      final text = infiniteCacheLayer.toString();
      for (final name in [
        'pageFn',
        'initialPageParam',
        'getNextPageParam',
        'getPreviousPageParam',
        'maxPages',
        'pages',
      ]) {
        expect(text, contains('$name: '));
      }
      expect(text, isNot(contains('queryFn: ')));
      expect(infiniteSelecting.toString(), contains('select: '));
    });
  });

  // The client's defaulting: each field changed alone changes the defaulted
  // options, by == and by hashCode.
  group('the client resolves every field into the Defaulted* options', () {
    late QueryClient client;
    setUp(() => client = testClient());
    tearDown(() => client.clear());

    void differsPerField<O>(
      O base,
      List<Field<O>> fields,
      Object Function(O options) resolve,
    ) {
      final resolved = resolve(base);
      expect(resolve(base), resolved);
      expect(resolve(base).hashCode, resolved.hashCode);
      for (final f in fields) {
        final changed = resolve(f.change(base));
        expect(changed == resolved, isFalse, reason: f.name);
        expect(changed.hashCode, isNot(resolved.hashCode), reason: f.name);
      }
    }

    test('QueryOptions -> DefaultedQueryOptions', () {
      differsPerField<QueryOptions<int>>(
        cacheLayer,
        [
          ..._queryOptionsFields<QueryOptions<int>, int>(
            (o, c) => o.copyWith(
              queryKey: c.queryKey,
              enabled: c.enabled,
              staleTime: c.staleTime,
              gcTime: c.gcTime,
              retry: c.retry,
              retryDelay: c.retryDelay,
              networkMode: c.networkMode,
              initialData: c.initialData,
              initialDataUpdatedAt: c.initialDataUpdatedAt,
              initialDataUpdatedAtCompute: c.initialDataUpdatedAtCompute,
              structuralSharing: c.structuralSharing,
              meta: c.meta,
            ),
            initialDataA: const InitialData.value(1),
            initialDataB: const InitialData.value(2),
          ),
          field('queryFn', (o) => o.queryFn, queryFnA,
              (o) => o.copyWith(queryFn: queryFnB)),
        ],
        client.defaultQueryOptions<int>,
      );
      final withCompute =
          cacheLayer.copyWith(initialDataUpdatedAtCompute: updatedAtA);
      expect(
          client.defaultQueryOptions(withCompute) ==
              client.defaultQueryOptions(withCompute.copyWith(
                  initialDataUpdatedAtCompute: updatedAtB)),
          isFalse);
    });

    test(
        'QueryObserverOptions and QuerySelectOptions -> '
        'DefaultedQueryObserverOptions', () {
      for (final base in <QueryObserverOptionsBase<int, int>>[
        plain,
        selecting
      ]) {
        differsPerField<QueryObserverOptionsBase<int, int>>(
          base,
          [
            ..._queryOptionsFields<QueryObserverOptionsBase<int, int>, int>(
              (o, c) => o.copyWith(
                queryKey: c.queryKey,
                enabled: c.enabled,
                staleTime: c.staleTime,
                gcTime: c.gcTime,
                retry: c.retry,
                retryDelay: c.retryDelay,
                networkMode: c.networkMode,
                initialData: c.initialData,
                initialDataUpdatedAt: c.initialDataUpdatedAt,
                initialDataUpdatedAtCompute: c.initialDataUpdatedAtCompute,
                structuralSharing: c.structuralSharing,
                meta: c.meta,
              ),
              initialDataA: const InitialData.value(1),
              initialDataB: const InitialData.value(2),
            ),
            field('queryFn', (o) => o.queryFn, queryFnA,
                (o) => o.copyWith(queryFn: queryFnB)),
            ..._observerFields<QueryObserverOptionsBase<int, int>>(
              read: (o) => (
                o.placeholderData,
                o.refetchOnMount,
                o.refetchOnWindowFocus,
                o.refetchOnReconnect,
                o.refetchInterval,
                o.refetchIntervalInBackground,
                o.retryOnMount,
              ),
              change: (o, c) => o.copyWith(
                placeholderData: c.placeholderData as PlaceholderData<int>?,
                refetchOnMount: c.refetchOnMount,
                refetchOnWindowFocus: c.refetchOnWindowFocus,
                refetchOnReconnect: c.refetchOnReconnect,
                refetchInterval: c.refetchInterval,
                refetchIntervalInBackground: c.refetchIntervalInBackground,
                retryOnMount: c.retryOnMount,
              ),
              placeholderA: const PlaceholderData<int>.value(1),
              placeholderB: const PlaceholderData<int>.value(2),
            ),
            if (base is QuerySelectOptions<int, int>)
              field('select', (o) => o.select, selectA,
                  (o) => base.copyWith(select: selectB)),
          ],
          client.defaultQueryObserverOptions<int, int>,
        );
      }
      final withCompute =
          plain.copyWith(initialDataUpdatedAtCompute: updatedAtA);
      expect(
          client.defaultQueryObserverOptions(withCompute) ==
              client.defaultQueryObserverOptions(withCompute.copyWith(
                  initialDataUpdatedAtCompute: updatedAtB)),
          isFalse);
    });

    test('infinite options -> DefaultedQueryObserverOptions over InfiniteData',
        () {
      for (final base in <InfiniteQueryObserverOptionsBase<int, int, Object?>>[
        infinite,
        infiniteSelecting,
      ]) {
        differsPerField<InfiniteQueryObserverOptionsBase<int, int, Object?>>(
          base,
          [
            ..._queryOptionsFields<
                InfiniteQueryObserverOptionsBase<int, int, Object?>,
                InfiniteData<int, int>>(
              (o, c) => o.copyWith(
                queryKey: c.queryKey,
                enabled: c.enabled,
                staleTime: c.staleTime,
                gcTime: c.gcTime,
                retry: c.retry,
                retryDelay: c.retryDelay,
                networkMode: c.networkMode,
                initialData: c.initialData,
                initialDataUpdatedAt: c.initialDataUpdatedAt,
                initialDataUpdatedAtCompute: c.initialDataUpdatedAtCompute,
                structuralSharing: c.structuralSharing,
                meta: c.meta,
              ),
              initialDataA: InitialData.value(_pages(1)),
              initialDataB: InitialData.value(_pages(2)),
            ),
            ...pagingFields<
                InfiniteQueryObserverOptionsBase<int, int, Object?>>((o,
                    {pageFn,
                    initialPageParam,
                    getNextPageParam,
                    getPreviousPageParam,
                    maxPages}) =>
                o.copyWith(
                  pageFn: pageFn,
                  initialPageParam: initialPageParam,
                  getNextPageParam: getNextPageParam,
                  getPreviousPageParam: getPreviousPageParam,
                  maxPages: maxPages,
                )),
            ..._observerFields<
                InfiniteQueryObserverOptionsBase<int, int, Object?>>(
              read: (o) => (
                o.placeholderData,
                o.refetchOnMount,
                o.refetchOnWindowFocus,
                o.refetchOnReconnect,
                o.refetchInterval,
                o.refetchIntervalInBackground,
                o.retryOnMount,
              ),
              change: (o, c) => o.copyWith(
                placeholderData: c.placeholderData
                    as PlaceholderData<InfiniteData<int, int>>?,
                refetchOnMount: c.refetchOnMount,
                refetchOnWindowFocus: c.refetchOnWindowFocus,
                refetchOnReconnect: c.refetchOnReconnect,
                refetchInterval: c.refetchInterval,
                refetchIntervalInBackground: c.refetchIntervalInBackground,
                retryOnMount: c.retryOnMount,
              ),
              placeholderA:
                  const PlaceholderData<InfiniteData<int, int>>.keepPrevious(),
              placeholderB:
                  PlaceholderData<InfiniteData<int, int>>.value(_pages(9)),
            ),
            if (base is InfiniteQuerySelectOptions<int, int, String>)
              field('select', (o) => o.select, selectPagesA,
                  (o) => base.copyWith(select: selectPagesB)),
          ],
          (o) => client
              .defaultQueryObserverOptions(client.infiniteObserverOptions(o)),
        );
      }
    });

    test('InfiniteQueryOptions.pages reaches the defaulted behaviour', () {
      expect(
          client.defaultQueryOptions(infiniteCacheLayer) ==
              client.defaultQueryOptions(infiniteCacheLayer.copyWith(pages: 5)),
          isFalse);
    });

    test('MutationOptions -> DefaultedMutationOptions', () {
      final base = client.defaultMutationOptions(_mutationOptions());
      expect(client.defaultMutationOptions(_mutationOptions()), base);
      expect(client.defaultMutationOptions(_mutationOptions()).hashCode,
          base.hashCode);
      for (final name in _mutationOptionFields) {
        final changed =
            client.defaultMutationOptions(_mutationOptions(vary: name));
        expect(changed == base, isFalse, reason: name);
        expect(changed.hashCode, isNot(base.hashCode), reason: name);
      }
      // The context form, against a base that has it rather than mutationFn.
      final withContext =
          client.defaultMutationOptions(_mutationOptions(vary: 'withContextA'));
      final otherContext =
          client.defaultMutationOptions(_mutationOptions(vary: 'withContextB'));
      expect(withContext == otherContext, isFalse);
      expect(withContext.hashCode, isNot(otherContext.hashCode));
    });
  });

  group('MutationOptions', () {
    test('the constructor stores every field', () {
      final options = _mutationOptions();
      expect((
        options.mutationKey,
        options.mutationFn,
        options.mutationFnWithContext,
        options.onMutate,
        options.onSuccess,
        options.onError,
        options.onSettled,
        options.retry,
        options.retryDelay,
        options.networkMode,
        options.gcTime,
        options.scope,
        options.meta,
      ), (
        _keyA,
        mutationFnA,
        null,
        onMutateA,
        onSuccessA,
        onErrorA,
        onSettledA,
        RetryPolicy.always,
        const RetryDelay.fixed(Duration(seconds: 1)),
        NetworkMode.always,
        GcTime.never,
        const MutationScope('a'),
        'metaA',
      ));
    });

    test('simple carries every field it takes', () {
      void onSuccess(int d, int v, void c) {}
      void onError(Object e, StackTrace s, int v, void c) {}
      void onSettled(int? d, Object? e, StackTrace? s, int v, void c) {}
      final options = MutationOptions.simple(
        mutationKey: _keyA,
        mutationFn: mutationFnA,
        onSuccess: onSuccess,
        onError: onError,
        onSettled: onSettled,
        retry: RetryPolicy.always,
        retryDelay: const RetryDelay.fixed(Duration(seconds: 1)),
        networkMode: NetworkMode.always,
        gcTime: GcTime.never,
        scope: const MutationScope('a'),
        meta: 'metaA',
      );
      expect((
        options.mutationKey,
        options.mutationFn,
        options.onSuccess,
        options.onError,
        options.onSettled,
        options.retry,
        options.retryDelay,
        options.networkMode,
        options.gcTime,
        options.scope,
        options.meta,
      ), (
        _keyA,
        mutationFnA,
        onSuccess,
        onError,
        onSettled,
        RetryPolicy.always,
        const RetryDelay.fixed(Duration(seconds: 1)),
        NetworkMode.always,
        GcTime.never,
        const MutationScope('a'),
        'metaA',
      ));
      Future<int> withContext(int v, MutationFunctionContext<void> c) async =>
          v;
      expect(
          MutationOptions.simple(mutationFnWithContext: withContext)
              .mutationFnWithContext,
          withContext);
    });
  });
}

const _one = 1;

const _queryDefaultFields = [
  'queryFn',
  'structuralSharing',
  'enabled',
  'staleTime',
  'gcTime',
  'retry',
  'retryDelay',
  'retryOnMount',
  'networkMode',
  'refetchOnMount',
  'refetchOnWindowFocus',
  'refetchOnReconnect',
  'refetchInterval',
  'refetchIntervalInBackground',
  'meta',
];

/// Every field set; [vary] changes one. With [sparse], only [vary] is set.
QueryDefaults _queryDefaults({String? vary, bool sparse = false}) {
  T? v<T>(String name, T a, T b) =>
      sparse && name != vary ? null : pick(name, vary, a, b);
  return QueryDefaults(
    queryFn: v('queryFn', erasedQueryFnA, erasedQueryFnB),
    structuralSharing: v('structuralSharing', erasedShareA, erasedShareB),
    enabled: v('enabled', Enabled.no, const Enabled.when(enabledWhenA)),
    staleTime: v('staleTime', StaleTime.infinite, StaleTime.static),
    gcTime: v('gcTime', GcTime.never, GcTime.defaultValue),
    retry: v('retry', RetryPolicy.always, RetryPolicy.never),
    retryDelay: v('retryDelay', RetryDelay.defaultValue,
        const RetryDelay.fixed(Duration.zero)),
    retryOnMount: v('retryOnMount', false, true),
    networkMode: v('networkMode', NetworkMode.always, NetworkMode.offlineFirst),
    refetchOnMount: v('refetchOnMount', RefetchOn.always, RefetchOn.never),
    refetchOnWindowFocus:
        v('refetchOnWindowFocus', RefetchOn.always, RefetchOn.never),
    refetchOnReconnect:
        v('refetchOnReconnect', RefetchOn.always, RefetchOn.never),
    refetchInterval: v('refetchInterval', RefetchInterval.off,
        const RefetchInterval.every(Duration(seconds: 1))),
    refetchIntervalInBackground: v('refetchIntervalInBackground', true, false),
    meta: v('meta', 'metaA', 'metaB'),
  );
}

const _mutationDefaultFields = [
  'mutationFn',
  'retry',
  'retryDelay',
  'networkMode',
  'gcTime',
  'scope',
  'meta',
];

MutationDefaults _mutationDefaults({String? vary, bool sparse = false}) {
  T? v<T>(String name, T a, T b) =>
      sparse && name != vary ? null : pick(name, vary, a, b);
  return MutationDefaults(
    mutationFn: v('mutationFn', erasedMutationFnA, erasedMutationFnB),
    retry: v('retry', RetryPolicy.always, RetryPolicy.never),
    retryDelay: v('retryDelay', RetryDelay.defaultValue,
        const RetryDelay.fixed(Duration.zero)),
    networkMode: v('networkMode', NetworkMode.always, NetworkMode.offlineFirst),
    gcTime: v('gcTime', GcTime.never, GcTime.defaultValue),
    scope: v('scope', const MutationScope('a'), const MutationScope('b')),
    meta: v('meta', 'metaA', 'metaB'),
  );
}

const _mutationOptionFields = [
  'mutationKey',
  'mutationFn',
  'onMutate',
  'onSuccess',
  'onError',
  'onSettled',
  'retry',
  'retryDelay',
  'networkMode',
  'gcTime',
  'scope',
  'meta',
];

MutationOptions<int, int, String> _mutationOptions({String? vary}) {
  final withContext = switch (vary) {
    'withContextA' => mutationFnWithContextA,
    'withContextB' => mutationFnWithContextB,
    _ => null,
  };
  return MutationOptions<int, int, String>(
    mutationKey: pick('mutationKey', vary, _keyA, _keyB),
    mutationFn: withContext != null
        ? null
        : pick('mutationFn', vary, mutationFnA, mutationFnB),
    mutationFnWithContext: withContext,
    onMutate: pick('onMutate', vary, onMutateA, onMutateB),
    onSuccess: pick('onSuccess', vary, onSuccessA, onSuccessB),
    onError: pick('onError', vary, onErrorA, onErrorB),
    onSettled: pick('onSettled', vary, onSettledA, onSettledB),
    retry: pick('retry', vary, RetryPolicy.always, RetryPolicy.never),
    retryDelay: pick('retryDelay', vary,
        const RetryDelay.fixed(Duration(seconds: 1)), RetryDelay.defaultValue),
    networkMode:
        pick('networkMode', vary, NetworkMode.always, NetworkMode.offlineFirst),
    gcTime: pick('gcTime', vary, GcTime.never, GcTime.defaultValue),
    scope:
        pick('scope', vary, const MutationScope('a'), const MutationScope('b')),
    meta: pick('meta', vary, 'metaA', 'metaB'),
  );
}

final _stackA = StackTrace.current;
final _stackB = StackTrace.fromString('b');

QueryState<int> _queryState({String? vary}) => QueryState<int>(
      hasData: pick('hasData', vary, true, false),
      data: pick('data', vary, 1, 2),
      dataUpdateCount: pick('dataUpdateCount', vary, 1, 2),
      dataUpdatedAt: pick('dataUpdatedAt', vary, _dateA, _dateB),
      error: pick('error', vary, 'boom', 'bang'),
      errorStackTrace: pick('errorStackTrace', vary, _stackA, _stackB),
      errorUpdateCount: pick('errorUpdateCount', vary, 1, 2),
      consecutiveErrorCount: pick('consecutiveErrorCount', vary, 1, 2),
      errorUpdatedAt: pick('errorUpdatedAt', vary, _dateA, _dateB),
      fetchFailureCount: pick('fetchFailureCount', vary, 1, 2),
      fetchFailureReason: pick('fetchFailureReason', vary, 'boom', 'bang'),
      fetchFailureStackTrace:
          pick('fetchFailureStackTrace', vary, _stackA, _stackB),
      fetchMeta: pick('fetchMeta', vary, 'metaA', 'metaB'),
      isInvalidated: pick('isInvalidated', vary, true, false),
      status: pick('status', vary, QueryStatus.error, QueryStatus.success),
      fetchStatus:
          pick('fetchStatus', vary, FetchStatus.fetching, FetchStatus.paused),
    );

QueryResult<int> _queryResult(String variant, {String? vary}) {
  final fetchStatus = vary == 'paused'
      ? FetchStatus.paused
      : pick('fetchStatus', vary, FetchStatus.fetching, FetchStatus.idle);
  final dataUpdatedAt = pick('dataUpdatedAt', vary, _dateA, _dateB);
  final errorUpdatedAt = pick('errorUpdatedAt', vary, _dateA, _dateB);
  final failureCount = pick('failureCount', vary, 1, 2);
  final failureReason = pick<Object>('failureReason', vary, 'boom', 'bang');
  final errorUpdateCount = pick('errorUpdateCount', vary, 1, 2);
  final consecutiveErrorCount = pick('consecutiveErrorCount', vary, 1, 2);
  final isStale = pick('isStale', vary, true, false);
  final isEnabled = pick('isEnabled', vary, true, false);
  final isFetched = pick('isFetched', vary, true, false);
  final isFetchedAfterMount = pick('isFetchedAfterMount', vary, true, false);
  final isPlaceholderData = pick('isPlaceholderData', vary, true, false);
  final data = pick('data', vary, 1, 2);
  return switch (variant) {
    'pending' => QueryPending<int>(
        fetchStatus: fetchStatus,
        dataUpdatedAt: dataUpdatedAt,
        errorUpdatedAt: errorUpdatedAt,
        failureCount: failureCount,
        failureReason: failureReason,
        failureStackTrace: _stackA,
        errorUpdateCount: errorUpdateCount,
        consecutiveErrorCount: consecutiveErrorCount,
        isStale: isStale,
        isEnabled: isEnabled,
        isFetched: isFetched,
        isFetchedAfterMount: isFetchedAfterMount,
        isPlaceholderData: isPlaceholderData,
        refetch: refetchA,
      ),
    'success' => QuerySuccess<int>(
        data: data,
        fetchStatus: fetchStatus,
        dataUpdatedAt: dataUpdatedAt,
        errorUpdatedAt: errorUpdatedAt,
        failureCount: failureCount,
        failureReason: failureReason,
        failureStackTrace: _stackA,
        errorUpdateCount: errorUpdateCount,
        consecutiveErrorCount: consecutiveErrorCount,
        isStale: isStale,
        isEnabled: isEnabled,
        isFetched: isFetched,
        isFetchedAfterMount: isFetchedAfterMount,
        isPlaceholderData: isPlaceholderData,
        refetch: refetchA,
      ),
    _ => QueryError<int>(
        error: pick('error', vary, 'boom', 'bang'),
        stackTrace: _stackA,
        staleData: data,
        hasStaleData: pick('hasStaleData', vary, true, false),
        fetchStatus: fetchStatus,
        dataUpdatedAt: dataUpdatedAt,
        errorUpdatedAt: errorUpdatedAt,
        failureCount: failureCount,
        failureReason: failureReason,
        failureStackTrace: _stackA,
        errorUpdateCount: errorUpdateCount,
        consecutiveErrorCount: consecutiveErrorCount,
        isStale: isStale,
        isEnabled: isEnabled,
        isFetched: isFetched,
        isFetchedAfterMount: isFetchedAfterMount,
        isPlaceholderData: isPlaceholderData,
        refetch: refetchA,
      ),
  };
}

MutationResult<int, int> _mutationResult(String variant, {String? vary}) {
  final variables = pick('variables', vary, 1, 2);
  final hasVariables = pick('hasVariables', vary, true, false);
  final failureCount = pick('failureCount', vary, 1, 2);
  final failureReason = pick<Object>('failureReason', vary, 'boom', 'bang');
  final isPaused = pick('isPaused', vary, true, false);
  final submittedAt = pick('submittedAt', vary, _dateA, _dateB);
  return switch (variant) {
    'idle' => MutationIdle<int, int>(
        variables: variables,
        hasVariables: hasVariables,
        failureCount: failureCount,
        failureReason: failureReason,
        isPaused: isPaused,
        submittedAt: submittedAt,
        mutate: mutateA,
        mutateAsync: mutateAsyncA,
        reset: resetA,
      ),
    'pending' => MutationPending<int, int>(
        variables: variables,
        hasVariables: hasVariables,
        failureCount: failureCount,
        failureReason: failureReason,
        isPaused: isPaused,
        submittedAt: submittedAt,
        mutate: mutateA,
        mutateAsync: mutateAsyncA,
        reset: resetA,
      ),
    'success' => MutationSuccess<int, int>(
        data: pick('data', vary, 1, 2),
        variables: variables,
        hasVariables: hasVariables,
        failureCount: failureCount,
        failureReason: failureReason,
        isPaused: isPaused,
        submittedAt: submittedAt,
        mutate: mutateA,
        mutateAsync: mutateAsyncA,
        reset: resetA,
      ),
    _ => MutationError<int, int>(
        error: pick('error', vary, 'boom', 'bang'),
        stackTrace: _stackA,
        variables: variables,
        hasVariables: hasVariables,
        failureCount: failureCount,
        failureReason: failureReason,
        isPaused: isPaused,
        submittedAt: submittedAt,
        mutate: mutateA,
        mutateAsync: mutateAsyncA,
        reset: resetA,
      ),
  };
}

/// The cache-layer fields, typed for one data type. [copy] is the shape's
/// own `copyWith`, handed a template whose non-null fields are the ones to
/// change — which keeps one table for every shape without a dynamic call.
List<Field<O>> _queryOptionsFields<O extends QueryOptions<T>, T>(
  O Function(O options, QueryOptions<T> changes) copy, {
  required InitialData<T> initialDataA,
  required InitialData<T> initialDataB,
}) {
  O change(O o, QueryOptions<T> changes) => copy(o, changes);
  return [
    field('queryKey', (o) => o.queryKey, _keyA,
        (o) => change(o, QueryOptions<T>(queryKey: _keyB))),
    field(
        'enabled',
        (o) => o.enabled,
        Enabled.no,
        (o) => change(o, QueryOptions<T>(queryKey: _keyA, enabled: Enabled.yes))
            ._keyFrom(o)),
    field(
        'staleTime',
        (o) => o.staleTime,
        StaleTime.infinite,
        (o) => change(
                o,
                QueryOptions<T>(
                    queryKey: _keyA,
                    staleTime: const StaleTime.duration(Duration(minutes: 1))))
            ._keyFrom(o)),
    field(
        'gcTime',
        (o) => o.gcTime,
        GcTime.never,
        (o) => change(
                o,
                QueryOptions<T>(
                    queryKey: _keyA,
                    gcTime: const GcTime.duration(Duration(seconds: 1))))
            ._keyFrom(o)),
    field(
        'retry',
        (o) => o.retry,
        RetryPolicy.always,
        (o) => change(
                o, QueryOptions<T>(queryKey: _keyA, retry: const RetryTimes(7)))
            ._keyFrom(o)),
    field(
        'retryDelay',
        (o) => o.retryDelay,
        const RetryDelay.fixed(Duration(seconds: 1)),
        (o) => change(
                o,
                QueryOptions<T>(
                    queryKey: _keyA,
                    retryDelay: const RetryDelay.fixed(Duration(seconds: 2))))
            ._keyFrom(o)),
    field(
        'networkMode',
        (o) => o.networkMode,
        NetworkMode.always,
        (o) => change(
                o,
                QueryOptions<T>(
                    queryKey: _keyA, networkMode: NetworkMode.offlineFirst))
            ._keyFrom(o)),
    field(
        'initialData',
        (o) => o.initialData,
        initialDataA,
        (o) => change(
                o, QueryOptions<T>(queryKey: _keyA, initialData: initialDataB))
            ._keyFrom(o)),
    field(
        'initialDataUpdatedAt',
        (o) => o.initialDataUpdatedAt,
        _dateA,
        (o) => change(o,
                QueryOptions<T>(queryKey: _keyA, initialDataUpdatedAt: _dateB))
            ._keyFrom(o)),
    field(
        'initialDataUpdatedAtCompute',
        (o) => o.initialDataUpdatedAtCompute,
        null,
        (o) => change(
                o,
                QueryOptions<T>(
                    queryKey: _keyA, initialDataUpdatedAtCompute: updatedAtB))
            ._keyFrom(o)),
    field(
        'structuralSharing',
        (o) => o.structuralSharing,
        shareA<T>,
        (o) => change(o,
                QueryOptions<T>(queryKey: _keyA, structuralSharing: shareB<T>))
            ._keyFrom(o)),
    field(
        'meta',
        (o) => o.meta,
        'metaA',
        (o) => change(o, QueryOptions<T>(queryKey: _keyA, meta: 'metaB'))
            ._keyFrom(o)),
  ];
}

extension<O extends QueryOptions<Object?>> on O {
  /// The template's `queryKey` is required, so every change passes one; this
  /// asserts it is the key the options already had, so no field but the
  /// intended one moved.
  O _keyFrom(O original) {
    expect(this.queryKey, original.queryKey);
    return this;
  }
}

/// The observer-only fields, for either observer base. [read] returns them
/// in declaration order; [change] is the shape's `copyWith`, handed a
/// template whose non-null fields are the ones to change.
List<Field<O>> _observerFields<O>({
  required (
    Object?,
    Object?,
    Object?,
    Object?,
    Object?,
    Object?,
    Object?,
  )
          Function(O o)
      read,
  required O Function(O o, _ObserverChanges c) change,
  required Object placeholderA,
  required Object placeholderB,
}) =>
    [
      field('placeholderData', (o) => read(o).$1, placeholderA,
          (o) => change(o, _ObserverChanges(placeholderData: placeholderB))),
      field('refetchOnMount', (o) => read(o).$2, RefetchOn.always,
          (o) => change(o, _ObserverChanges(refetchOnMount: RefetchOn.never))),
      field(
          'refetchOnWindowFocus',
          (o) => read(o).$3,
          RefetchOn.always,
          (o) => change(
              o, _ObserverChanges(refetchOnWindowFocus: RefetchOn.never))),
      field(
          'refetchOnReconnect',
          (o) => read(o).$4,
          RefetchOn.always,
          (o) =>
              change(o, _ObserverChanges(refetchOnReconnect: RefetchOn.never))),
      field(
          'refetchInterval',
          (o) => read(o).$5,
          const RefetchInterval.every(Duration(seconds: 1)),
          (o) => change(
              o,
              _ObserverChanges(
                  refetchInterval:
                      const RefetchInterval.every(Duration(seconds: 2))))),
      field(
          'refetchIntervalInBackground',
          (o) => read(o).$6,
          true,
          (o) =>
              change(o, _ObserverChanges(refetchIntervalInBackground: false))),
      field('retryOnMount', (o) => read(o).$7, false,
          (o) => change(o, _ObserverChanges(retryOnMount: true))),
    ];

class _Behavior implements FetchBehavior<int> {
  @override
  void onFetch(FetchContext<int> context, Query<int> query) {}
}

class _ObserverChanges {
  _ObserverChanges({
    this.placeholderData,
    this.refetchOnMount,
    this.refetchOnWindowFocus,
    this.refetchOnReconnect,
    this.refetchInterval,
    this.refetchIntervalInBackground,
    this.retryOnMount,
  });

  final Object? placeholderData;
  final RefetchOn? refetchOnMount;
  final RefetchOn? refetchOnWindowFocus;
  final RefetchOn? refetchOnReconnect;
  final RefetchInterval? refetchInterval;
  final bool? refetchIntervalInBackground;
  final bool? retryOnMount;
}
