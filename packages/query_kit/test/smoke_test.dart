/// Port-specific smoke tests: the wiring the ported suites assume works.
///
/// Upstream has no counterpart for these, so they live outside the
/// one-file-per-upstream-file mapping
/// (https://github.com/KoTTi97/flutter_query/issues/18).
library;

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('QueryKey', () {
    test('equal keys are equal and hash alike', () {
      final a = QueryKey(<Object?>['tasks', 1]);
      final b = QueryKey(<Object?>['tasks', 1]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('maps compare without regard to entry order', () {
      final a = QueryKey(<Object?>[
        'tasks',
        <String, Object?>{'project': 'website', 'status': 'active'},
      ]);
      final b = QueryKey(<Object?>[
        'tasks',
        <String, Object?>{'status': 'active', 'project': 'website'},
      ]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('a prefix matches, an unrelated key does not', () {
      final key = QueryKey(<Object?>['tasks', 3, 'readings']);
      expect(key.matches(QueryKey(<Object?>['tasks'])), isTrue);
      expect(key.matches(QueryKey(<Object?>['tasks', 3])), isTrue);
      expect(key.matches(QueryKey(<Object?>['tasks', 4])), isFalse);
      expect(key.matches(QueryKey(<Object?>['tasks']), exact: true), isFalse);
    });

    test('a filter map matches on the entries it names', () {
      final key = QueryKey(<Object?>[
        'tasks',
        <String, Object?>{'project': 'website', 'status': 'active'},
      ]);
      expect(
        key.matches(
          QueryKey(<Object?>[
            'tasks',
            <String, Object?>{'project': 'website'},
          ]),
        ),
        isTrue,
      );
      expect(
        key.matches(
          QueryKey(<Object?>[
            'tasks',
            <String, Object?>{'project': 'inbox'},
          ]),
        ),
        isFalse,
      );
    });

    test('mutating a list after construction cannot corrupt the key', () {
      final parts = <Object?>['tasks', 1];
      final key = QueryKey(<Object?>[parts]);
      parts.add(2);
      expect(
        key,
        equals(
          QueryKey(<Object?>[
            <Object?>['tasks', 1],
          ]),
        ),
      );
    });
  });

  group('a query through its lifecycle', () {
    testFakeAsync('fetches, resolves, and reports success', (time) async {
      final client = testClient();
      final key = queryKey();

      final observer = QueryObserver<String, String>(
        client,
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (context) async {
            await sleep(ms(10));
            return 'data';
          },
        ),
      );

      final seen = <QueryResult<String>>[];
      final unsubscribe = observer.subscribe(seen.add);

      expect(observer.currentResult, isA<QueryPending<String>>());
      expect(observer.currentResult.isLoading, isTrue);

      await time.advance(ms(11));

      expect(observer.currentResult, isA<QuerySuccess<String>>());
      expect(
        (observer.currentResult as QuerySuccess<String>).data,
        equals('data'),
      );
      expect(client.getQueryData<String>(key), equals('data'));
      expect(seen, isNotEmpty);

      unsubscribe();
    });

    testFakeAsync('an error keeps stale data on the result', (time) async {
      final client = testClient();
      final key = queryKey();
      var attempt = 0;

      final observer = QueryObserver<String, String>(
        client,
        QueryObserverOptions<String>(
          queryKey: key,
          retry: RetryPolicy.never,
          staleTime: StaleTime.zero,
          queryFn: (context) async {
            attempt++;
            if (attempt == 1) {
              return 'first';
            }
            throw StateError('boom');
          },
        ),
      );

      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(1));
      expect(observer.currentResult, isA<QuerySuccess<String>>());

      await observer.refetch();
      await time.advance(ms(1));

      final result = observer.currentResult;
      expect(result, isA<QueryError<String>>());
      final error = result as QueryError<String>;
      expect(error.error, isA<StateError>());
      expect(error.staleData, equals('first'));
      expect(error.isRefetchError, isTrue);

      unsubscribe();
    });

    testFakeAsync('select narrows what the observer reports', (time) async {
      final client = testClient();
      final key = queryKey();

      final observer = QueryObserver<Map<String, Object?>, String>(
        client,
        QuerySelectOptions<Map<String, Object?>, String>(
          queryKey: key,
          queryFn: (context) async => <String, Object?>{'name': 'website'},
          select: (data) => data['name']! as String,
        ),
      );

      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(1));

      expect(observer.currentResult, isA<QuerySuccess<String>>());
      expect(
        (observer.currentResult as QuerySuccess<String>).data,
        equals('website'),
      );

      unsubscribe();
    });

    testFakeAsync('reading one key as two types throws', (time) async {
      final client = testClient();
      final key = queryKey();

      client.setQueryData<String>(key, 'text');

      expect(
        () => client.getQueryData<int>(key),
        throwsA(isA<QueryDataTypeError>()),
      );
      expect(client.getQueryData<String>(key), equals('text'));
    });
  });

  group('a mutation', () {
    testFakeAsync('runs, reports success, and rolls back on error', (
      time,
    ) async {
      final client = testClient();
      final rollbacks = <String>[];

      final observer = MutationObserver<String, int, String>(
        client,
        MutationOptions<String, int, String>(
          mutationFn: (variables) async {
            await sleep(ms(5));
            if (variables < 0) {
              throw ArgumentError('negative');
            }
            return 'value $variables';
          },
          onMutate: (variables) => 'snapshot $variables',
          onError: (error, stackTrace, variables, onMutateResult) {
            rollbacks.add(onMutateResult!);
          },
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      observer.mutate(1);
      expect(observer.currentResult, isA<MutationPending<String, int>>());

      await time.advance(ms(6));
      expect(observer.currentResult, isA<MutationSuccess<String, int>>());
      expect(
        (observer.currentResult as MutationSuccess<String, int>).data,
        equals('value 1'),
      );

      observer.mutate(-1);
      await time.advance(ms(6));

      expect(observer.currentResult, isA<MutationError<String, int>>());
      expect(rollbacks, equals(<String>['snapshot -1']));

      unsubscribe();
    });
  });
}
