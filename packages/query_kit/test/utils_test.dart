/// Port of the applicable parts of `query-core/src/__tests__/utils.test.tsx` at
/// upstream `50680b98c`. Most of that file tests JavaScript helpers this port
/// has no counterpart for; the omissions are enumerated in
/// `test/PORTING_NOTES.md`.
library;

// The unit under test is internal plumbing the package does not export.
import 'package:query_kit/query_kit.dart';
import 'package:query_kit/src/infinite_query.dart';
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

      testFakeAsync(
          'should consume the signal only once across repeated accesses',
          (time) async {
        // Upstream counts `addEventListener` calls on the signal, which its
        // getter makes exactly once; here the same "consumed" moment is the
        // `onSignalRead` callback the query hands the context, so that is
        // what is counted. Both assert that reading twice returns the same
        // token and consumes it once (pre-release review, 2026-09-12, P11).
        final token = QueryCancelToken();
        var consumed = 0;

        final context = QueryFunctionContext(
          client: testClient(),
          queryKey: queryKey(),
          signal: token,
          onSignalRead: () => consumed++,
        );

        expect(context.signal, same(token));
        expect(context.signal, same(token));

        expect(consumed, 1);
      });
    });

    group('replaceEqualDeep', () {
      test(
          'should return the previous value when the next value is an equal '
          'primitive', () {
        expect(replaceEqualDeep(1, 1), 1);
        expect(replaceEqualDeep('1', '1'), '1');
        expect(replaceEqualDeep(true, true), isTrue);
        expect(replaceEqualDeep(false, false), isFalse);
        expect(replaceEqualDeep<Object?>(null, null), isNull);
      });

      test(
          'should return the next value when the previous value is a '
          'different value', () {
        final date1 = DateTime(2020);
        final date2 = DateTime(2021);
        expect(replaceEqualDeep(1, 0), 0);
        expect(replaceEqualDeep(1, 2), 2);
        expect(replaceEqualDeep('1', '2'), '2');
        expect(replaceEqualDeep(true, false), isFalse);
        expect(replaceEqualDeep(false, true), isTrue);
        expect(replaceEqualDeep(date1, date2), same(date2));
      });

      test(
          'should return the next value when the previous value is a '
          'different type', () {
        final array = <int>[1];
        final object = <String, String>{'a': 'a'};
        expect(replaceEqualDeep<Object?>(0, null), isNull);
        expect(replaceEqualDeep<Object?>(null, 0), 0);
        expect(replaceEqualDeep<Object?>(<String, int>{}, null), isNull);
        expect(replaceEqualDeep<Object?>(<int>[], null), isNull);
        expect(replaceEqualDeep<Object?>(array, object), same(object));
        expect(replaceEqualDeep<Object?>(object, array), same(array));
      });

      test(
          'should return the previous value when the next value is an equal '
          'array', () {
        final prev = <int>[1, 2];
        final next = <int>[1, 2];
        expect(replaceEqualDeep(prev, next), same(prev));
      });

      test(
          'should return a copy when the previous value is a different array '
          'subset', () {
        final prev = <int>[1, 2];
        final next = <int>[1, 2, 3];
        final result = replaceEqualDeep(prev, next);
        expect(result, next);
        expect(result, isNot(same(prev)));
        expect(result, isNot(same(next)));
      });

      test(
          'should return a copy when the previous value is a different array '
          'superset', () {
        final prev = <int>[1, 2, 3];
        final next = <int>[1, 2];
        final result = replaceEqualDeep(prev, next);
        expect(result, next);
        expect(result, isNot(same(prev)));
        expect(result, isNot(same(next)));
      });

      test(
          'should return the previous value when the next value is an equal '
          'empty array', () {
        final prev = <Object?>[];
        final next = <Object?>[];
        expect(replaceEqualDeep(prev, next), same(prev));
      });

      test(
          'should return the previous value when the next value is an equal '
          'empty object', () {
        final prev = <String, Object?>{};
        final next = <String, Object?>{};
        expect(replaceEqualDeep(prev, next), same(prev));
      });

      test(
          'should return the previous value when the next value is an equal '
          'object', () {
        final prev = <String, String>{'a': 'a'};
        final next = <String, String>{'a': 'a'};
        expect(replaceEqualDeep(prev, next), same(prev));
      });

      // Adapted: a map is shared whole here, so a changed map is `next`
      // itself rather than a copy with `a` shared (see `replaceEqualDeep`).
      test('should replace different values in objects', () {
        final prev = <String, Object?>{
          'a': <String, String>{'b': 'b'},
          'c': 'c',
        };
        final next = <String, Object?>{
          'a': <String, String>{'b': 'b'},
          'c': 'd',
        };
        final result = replaceEqualDeep(prev, next);
        expect(result, next);
        expect(result, isNot(same(prev)));
        expect(result, same(next));
      });

      // Adapted at `result[2]`: the changed map is `next[2]` itself.
      test('should replace different values in arrays', () {
        final prev = <Object?>[
          1,
          <String, String>{'a': 'a'},
          <String, Object?>{
            'b': <String, String>{'b': 'b'}
          },
          <int>[1],
        ];
        final next = <Object?>[
          1,
          <String, String>{'a': 'a'},
          <String, Object?>{
            'b': <String, String>{'b': 'c'}
          },
          <int>[1],
        ];
        final result = replaceEqualDeep(prev, next);
        expect(result, next);
        expect(result, isNot(same(prev)));
        expect(result, isNot(same(next)));
        expect(result[0], same(prev[0]));
        expect(result[1], same(prev[1]));
        expect(result[2], same(next[2]));
        expect(result[3], same(prev[3]));
      });

      test(
          'should replace different values in arrays when the next value is '
          'a subset', () {
        final prev = <Map<String, String>>[
          {'a': 'a'},
          {'b': 'b'},
          {'c': 'c'},
        ];
        final next = <Map<String, String>>[
          {'a': 'a'},
          {'b': 'b'},
        ];
        final result = replaceEqualDeep(prev, next);
        expect(result, next);
        expect(result, isNot(same(prev)));
        expect(result, isNot(same(next)));
        expect(result[0], same(prev[0]));
        expect(result[1], same(prev[1]));
        expect(result, hasLength(2));
      });

      test(
          'should replace different values in arrays when the next value is '
          'a superset', () {
        final prev = <Map<String, String>>[
          {'a': 'a'},
          {'b': 'b'},
        ];
        final next = <Map<String, String>>[
          {'a': 'a'},
          {'b': 'b'},
          {'c': 'c'},
        ];
        final result = replaceEqualDeep(prev, next);
        expect(result, next);
        expect(result, isNot(same(prev)));
        expect(result, isNot(same(next)));
        expect(result[0], same(prev[0]));
        expect(result[1], same(prev[1]));
        expect(result[2], same(next[2]));
      });

      // Upstream's "not arrays or objects" is a `Map` instance, which JSON
      // does not walk; here that role is played by a class without `==`.
      test('should copy objects which are not arrays or objects', () {
        final opaque = Object();
        final prev = <Object?>[
          <String, String>{'a': 'a'},
          <String, String>{'b': 'b'},
          <String, String>{'c': 'c'},
          1,
        ];
        final next = <Object?>[
          <String, String>{'a': 'a'},
          opaque,
          <String, String>{'c': 'c'},
          2,
        ];
        final result = replaceEqualDeep(prev, next);
        expect(result, isNot(same(prev)));
        expect(result, isNot(same(next)));
        expect(result[0], same(prev[0]));
        expect(result[1], same(next[1]));
        expect(result[2], same(prev[2]));
        expect(result[3], next[3]);
      });

      test('should support equal objects which are not arrays or objects', () {
        final opaque = Object();
        final prev = <Object?>[
          opaque,
          <int>[1]
        ];
        final next = <Object?>[
          opaque,
          <int>[1]
        ];
        expect(replaceEqualDeep(prev, next), same(prev));
      });

      test('should support non equal objects which are not arrays or objects',
          () {
        final opaque1 = Object();
        final opaque2 = Object();
        final prev = <Object?>[
          opaque1,
          <int>[1]
        ];
        final next = <Object?>[
          opaque2,
          <int>[1]
        ];
        final result = replaceEqualDeep(prev, next);
        expect(result, isNot(same(prev)));
        expect(result, isNot(same(next)));
        expect(result[0], same(next[0]));
        expect(result[1], same(prev[1]));
      });

      // Adapted: maps are shared whole, so a changed nested map replaces its
      // parents with `next` outright.
      test('should replace all parent objects if some nested value changes',
          () {
        final prev = <String, Object?>{
          'todo': <String, Object?>{
            'id': '1',
            'meta': <String, int>{'createdAt': 0},
            'state': <String, bool>{'done': false},
          },
        };
        final next = <String, Object?>{
          'todo': <String, Object?>{
            'id': '1',
            'meta': <String, int>{'createdAt': 0},
            'state': <String, bool>{'done': true},
          },
        };
        final result = replaceEqualDeep(prev, next);
        expect(result, next);
        expect(result, same(next));
      });

      // Adapted the same way, with the list inside the map: the list is
      // walked, but the map holding it is replaced whole.
      test('should replace all parent arrays if some nested value changes', () {
        final prev = <String, Object?>{
          'todos': <Map<String, Object?>>[
            {
              'id': '1',
              'state': <String, bool>{'done': false}
            },
            {
              'id': '2',
              'state': <String, bool>{'done': true}
            },
          ],
        };
        final next = <String, Object?>{
          'todos': <Map<String, Object?>>[
            {
              'id': '1',
              'state': <String, bool>{'done': true}
            },
            {
              'id': '2',
              'state': <String, bool>{'done': true}
            },
          ],
        };
        final result = replaceEqualDeep(prev, next);
        expect(result, next);
        expect(result, same(next));

        final todos = replaceEqualDeep(
          prev['todos'] as List<Object?>,
          next['todos'] as List<Object?>,
        );
        expect(todos[0], same((next['todos'] as List<Object?>)[0]));
        expect(todos[1], same((prev['todos'] as List<Object?>)[1]));
      });

      test(
          'should correctly handle objects with the same number of properties '
          'and one property being undefined', () {
        final obj1 = <String, int?>{'a': 2, 'c': 123};
        final obj2 = <String, int?>{'a': 2, 'b': null};
        expect(replaceEqualDeep(obj1, obj2), same(obj2));
      });

      test('should be able to share values that contain undefined', () {
        final current = <Map<String, Object?>>[
          {'data': null, 'foo': true},
        ];
        final next = replaceEqualDeep(current, <Map<String, Object?>>[
          {'data': null, 'foo': true},
        ]);
        expect(next, same(current));
      });

      test(
          'should return the previous value when both values are an array of '
          'undefined', () {
        final current = <Object?>[null];
        expect(replaceEqualDeep(current, <Object?>[null]), same(current));
      });

      test(
          'should return the previous value when both values are an array '
          'that contains undefined', () {
        final current = <Object?>[
          <String, int>{'foo': 1},
          null,
        ];
        expect(
          replaceEqualDeep(current, <Object?>[
            <String, int>{'foo': 1},
            null,
          ]),
          same(current),
        );
      });

      // Nested lists rather than objects, so that the walk — and its limit —
      // is exercised.
      test(
          'should stop structural sharing once the recursion depth exceeds '
          'the limit', () {
        List<Object?> nest(int depth, int leaf) {
          Object? value = <Object?>[leaf];
          for (var i = 0; i < depth; i++) {
            value = <Object?>[value];
          }
          return value as List<Object?>;
        }

        final prev = nest(502, 1);
        final next = nest(502, 2);
        final result = replaceEqualDeep(prev, next);

        Object? resultNode = result;
        Object? nextNode = next;
        for (var i = 0; i < 502; i++) {
          resultNode = (resultNode as List<Object?>)[0];
          nextNode = (nextNode as List<Object?>)[0];
        }
        expect(resultNode, same(nextNode));
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
