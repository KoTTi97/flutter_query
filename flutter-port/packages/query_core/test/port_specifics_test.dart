import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Behaviour the port introduces, with no upstream test to mirror.
///
/// Each case exists because a design decision replaced something JavaScript
/// expressed differently — `undefined` versus `null`, magic option values
/// versus sealed types, one hash key versus a typed one. Everything that *does*
/// have an upstream counterpart lives in the per-suite port files instead.
void main() {
  late QueryClient queryClient;
  late QueryCache queryCache;

  setUp(() {
    queryClient = QueryClient();
    queryCache = queryClient.queryCache;
  });

  tearDown(() => queryClient.clear());

  Query<String> buildQuery(
    QueryKey key, {
    QueryFn<String>? queryFn,
    String? Function()? initialData,
    String Function(String? oldData, String newData)? structuralSharing,
  }) => queryCache.build<String>(
    queryClient.defaultQueryOptions(
      QueryObserverOptions<String, String>(
        queryKey: key,
        queryFn: queryFn,
        initialData: initialData,
        structuralSharing: structuralSharing,
      ),
    ),
  );

  group('null in place of undefined', () {
    test('initialData returning null means no data', () {
      final query = buildQuery(queryKey(), initialData: () => null);

      expect(query.state.hasData, isFalse);
      expect(query.state.status, QueryStatus.pending);
    });

    test('a setQueryData updater returning null aborts the write', () {
      final key = queryKey();
      queryClient.setQueryData<String>(key, (_) => 'first');

      final result = queryClient.setQueryData<String>(key, (_) => null);

      expect(result, isNull);
      expect(
        queryClient.getQueryData<String>(key),
        'first',
        reason: 'declining to update must not clear what is cached',
      );
    });

    test(
      'setQueryData on an unknown key with a null updater creates nothing',
      () {
        final key = queryKey();
        expect(queryClient.setQueryData<String>(key, (_) => null), isNull);
        expect(queryCache.find(key), isNull);
      },
    );
  });

  group('StaleDuration variants', () {
    testFakeAsync('a duration goes stale once it elapses', (time) async {
      final query = buildQuery(queryKey())..setData('data');

      const staleTime = StaleDuration.of(Duration(minutes: 1));
      expect(query.isStaleByTime(staleTime), isFalse);

      await time.advance(const Duration(seconds: 61));
      expect(query.isStaleByTime(staleTime), isTrue);
    });

    testFakeAsync('infinity never goes stale by time', (time) async {
      final query = buildQuery(queryKey())..setData('data');

      await time.advance(const Duration(days: 365));
      expect(query.isStaleByTime(StaleDuration.infinity), isFalse);
    });

    testFakeAsync('static ignores invalidation, where infinity does not', (
      time,
    ) async {
      final query = buildQuery(queryKey())
        ..setData('data')
        ..invalidate();

      expect(query.isStaleByTime(StaleDuration.static_), isFalse);
      expect(query.isStaleByTime(StaleDuration.infinity), isTrue);
      expect(query.isStaleByTime(StaleDuration.zero), isTrue);
      await time.flushMicrotasks();
    });

    test('resolve is collapsed against the query on each check', () {
      final query = buildQuery(queryKey())..setData('data');
      var calls = 0;

      final resolved = StaleDuration.resolve((_) {
        calls++;
        return StaleDuration.infinity;
      });

      expect(query.isStaleByTime(resolved), isFalse);
      expect(query.isStaleByTime(resolved), isFalse);
      expect(calls, 2, reason: 'it is re-evaluated, not memoized');
    });
  });

  group('structural sharing', () {
    test('is off unless supplied, so new data replaces old wholesale', () {
      final query = buildQuery(queryKey())..setData('first');
      query.setData('second');

      expect(query.state.data, 'second');
    });

    test('a supplied hook decides what is stored', () {
      final query = buildQuery(
        queryKey(),
        structuralSharing: (oldData, newData) => '${oldData ?? ''}$newData',
      )..setData('a');

      query.setData('b');

      expect(query.state.data, 'ab');
    });
  });

  group('typed cache entries', () {
    test('get throws when a key is reused with another data type', () {
      final key = queryKey();
      queryClient.setQueryData<String>(key, (_) => 'text');

      expect(() => queryCache.get<int>(key), throwsStateError);
    });

    test('get returns null for an unknown key rather than creating one', () {
      final key = queryKey();
      expect(queryCache.get<String>(key), isNull);
      expect(queryCache.queries, isEmpty);
    });
  });

  group('QueryKey equality', () {
    test('a key is the map key, so equal keys are the same entry', () {
      final first = queryCache.build<String>(
        queryClient.defaultQueryOptions(
          const QueryObserverOptions<String, String>(
            queryKey: QueryKey(['sensors', 1]),
          ),
        ),
      );
      final second = queryCache.build<String>(
        queryClient.defaultQueryOptions(
          const QueryObserverOptions<String, String>(
            queryKey: QueryKey(['sensors', 1]),
          ),
        ),
      );

      expect(second, same(first));
      expect(queryCache.queries, hasLength(1));
    });
  });
}
