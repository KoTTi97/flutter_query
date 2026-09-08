/// Port of the applicable parts of `query-core/src/__tests__/utils.test.tsx` at
/// upstream `50680b98c`. Most of that file tests JavaScript helpers this port
/// has no counterpart for; the omissions are enumerated in
/// `test/PORTING_NOTES.md`.
library;

import 'package:tanstack_query_core/tanstack_query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('core/utils', () {
    group('partialMatchKey', () {
      test('should return `true` if a includes b', () {
        final a = QueryKey(<Object?>[
          <String, Object?>{
            'a': <String, Object?>{'b': 'b'},
            'c': 'c',
            'd': <Object?>[
              <String, Object?>{'d': 'd '}
            ],
          }
        ]);
        final b = QueryKey(<Object?>[
          <String, Object?>{
            'a': <String, Object?>{'b': 'b'},
            'c': 'c',
            'd': <Object?>[],
          }
        ]);
        expect(a.matches(b), isTrue);
      });

      test('should return `false` if a does not include b', () {
        final a = QueryKey(<Object?>[
          <String, Object?>{
            'a': <String, Object?>{'b': 'b'},
            'c': 'c',
            'd': <Object?>[],
          }
        ]);
        final b = QueryKey(<Object?>[
          <String, Object?>{
            'a': <String, Object?>{'b': 'b'},
            'c': 'c',
            'd': <Object?>[
              <String, Object?>{'d': 'd '}
            ],
          }
        ]);
        expect(a.matches(b), isFalse);
      });

      test('should return `true` if array a includes array b', () {
        expect(
          QueryKey(<Object?>[1, 2, 3]).matches(QueryKey(<Object?>[1, 2])),
          isTrue,
        );
      });

      test('should return `false` if a is null and b is not', () {
        final a = QueryKey(<Object?>[null]);
        final b = QueryKey(<Object?>[
          <String, Object?>{'a': 'a'}
        ]);
        expect(a.matches(b), isFalse);
      });

      test('should return `false` if a contains null and b is not', () {
        final a = QueryKey(<Object?>[
          <String, Object?>{'a': null, 'c': 'c'}
        ]);
        final b = QueryKey(<Object?>[
          <String, Object?>{
            'a': <String, Object?>{'b': 'b'},
            'c': 'c',
          }
        ]);
        expect(a.matches(b), isFalse);
      });

      test('should return `false` if b is null and a is not', () {
        final a = QueryKey(<Object?>[
          <String, Object?>{'a': 'a'}
        ]);
        final b = QueryKey(<Object?>[null]);
        expect(a.matches(b), isFalse);
      });

      test('should return `false` if b contains null and a is not', () {
        final a = QueryKey(<Object?>[
          <String, Object?>{
            'a': <String, Object?>{'b': 'b'},
            'c': 'c',
          }
        ]);
        final b = QueryKey(<Object?>[
          <String, Object?>{'a': null, 'c': 'c'}
        ]);
        expect(a.matches(b), isFalse);
      });

      test('should not treat a null object property as a missing property', () {
        final withNull = QueryKey(<Object?>[
          'todos',
          <String, Object?>{'filters': null}
        ]);
        final withoutProperty =
            QueryKey(<Object?>['todos', <String, Object?>{}]);

        // Upstream reads both directions as `undefined === undefined` and
        // matches. Here `null` is a value, and a filter that names
        // `filters: null` is asking for an entry the other key does not have —
        // which is also what `==` says about these two keys, so partial
        // matching agrees with exact matching instead of contradicting it.
        expect(withoutProperty.matches(withNull), isFalse);
        expect(withNull.matches(withoutProperty), isTrue);
      });
    });

    group('matchMutation', () {
      testFakeAsync('should return false if mutationKey options is undefined',
          (time) async {
        final client = testClient();
        final filters = MutationFilters(mutationKey: queryKey());
        final mutation = client.mutationCache.build<void, void, void>(
          client,
          client.defaultMutationOptions<void, void, void>(
            const MutationOptions<void, void, void>(),
          ),
        );
        expect(filters.matches(mutation), isFalse);
      });
    });

    group('hashKey', () {
      test('should hash primitives correctly', () {
        expect(QueryKey(<Object?>['test']).debugString, '["test"]');
        expect(QueryKey(<Object?>[123]).debugString, '[123]');
        expect(QueryKey(<Object?>[null]).debugString, '[null]');
      });

      test('should hash objects with sorted keys consistently', () {
        final key1 = QueryKey(<Object?>[
          <String, Object?>{'b': 2, 'a': 1}
        ]);
        final key2 = QueryKey(<Object?>[
          <String, Object?>{'a': 1, 'b': 2}
        ]);

        expect(key1.debugString, key2.debugString);
        expect(key1.debugString, '[{"a":1,"b":2}]');
      });

      test('should hash arrays consistently', () {
        final arr1 = QueryKey(<Object?>[
          <String, Object?>{'b': 2, 'a': 1},
          'test',
          123,
        ]);
        final arr2 = QueryKey(<Object?>[
          <String, Object?>{'a': 1, 'b': 2},
          'test',
          123,
        ]);

        expect(arr1.debugString, arr2.debugString);
      });

      test('should handle nested objects with sorted keys', () {
        final nested1 = QueryKey(<Object?>[
          <String, Object?>{
            'a': <String, Object?>{'d': 4, 'c': 3},
            'b': 2,
          }
        ]);
        final nested2 = QueryKey(<Object?>[
          <String, Object?>{
            'b': 2,
            'a': <String, Object?>{'c': 3, 'd': 4},
          }
        ]);

        expect(nested1.debugString, nested2.debugString);
      });
    });

    group('the query function context signal', () {
      testFakeAsync(
          'should expose the signal on the context while preserving its other '
          'properties', (time) async {
        final client = testClient();
        final key = queryKey();
        final token = QueryCancelToken();
        final context = QueryFunctionContext(
          client: client,
          queryKey: key,
          signal: token,
        );

        expect(context.queryKey, same(key));
        expect(context.signal, same(token));
      });

      testFakeAsync(
          'should call onCancel immediately when the token is already cancelled '
          'on first access', (time) async {
        final token = QueryCancelToken()..cancel();
        var cancelled = 0;

        final context = QueryFunctionContext(
          client: testClient(),
          queryKey: queryKey(),
          signal: token,
        );

        context.signal.onCancel(() => cancelled++);

        expect(cancelled, 1);
      });

      testFakeAsync(
          'should flag cancellation when the consumed token is cancelled',
          (time) async {
        final token = QueryCancelToken();
        var cancelled = false;

        final context = QueryFunctionContext(
          client: testClient(),
          queryKey: queryKey(),
          signal: token,
        );

        context.signal.onCancel(() => cancelled = true);
        expect(cancelled, isFalse);

        token.cancel();
        await time.flushMicrotasks();

        expect(cancelled, isTrue);
      });
    });

    group('addToEnd', () {
      test('should add item to the end of the array', () {
        expect(addToEnd<int>(<int>[1, 2, 3], 4), <int>[1, 2, 3, 4]);
      });

      test('should not exceed max if provided', () {
        expect(addToEnd<int>(<int>[1, 2, 3], 4, 3), <int>[2, 3, 4]);
      });

      test('should add item to the end of the array when max = 0', () {
        expect(addToEnd<int>(<int>[1, 2, 3], 4, 0), <int>[1, 2, 3, 4]);
      });

      test('should add item to the end of the array when max is undefined', () {
        expect(addToEnd<int>(<int>[1, 2, 3], 4), <int>[1, 2, 3, 4]);
      });
    });

    group('addToStart', () {
      test('should add an item to the start of the array', () {
        expect(addToStart<int>(<int>[1, 2, 3], 4), <int>[4, 1, 2, 3]);
      });

      test('should respect the max argument', () {
        // One item falls off per call, not "trim down to max": pages arrive
        // one at a time.
        expect(addToStart<int>(<int>[1, 2, 3], 4, 2), <int>[4, 1, 2]);
      });

      test('should not remove any items if max = 0', () {
        expect(addToStart<int>(<int>[1, 2, 3], 4, 0), <int>[4, 1, 2, 3]);
      });

      test('should not remove any items if max is undefined', () {
        expect(addToStart<int>(<int>[1, 2, 3], 4), <int>[4, 1, 2, 3]);
      });
    });
  });
}
