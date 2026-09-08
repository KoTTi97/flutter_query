import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

/// Ports the key-related cases from upstream `utils.test.tsx`
/// (`hashKey` and `partialMatchKey` describes). Upstream asserts on hashed
/// strings; here the equivalent assertion is key equality, since QueryKey is
/// the map key directly.
void main() {
  group('QueryKey equality', () {
    test('equal keys are equal regardless of identity', () {
      expect(const QueryKey(['todos']), const QueryKey(['todos']));
      expect(
        const QueryKey(['todos']).hashCode,
        const QueryKey(['todos']).hashCode,
      );
    });

    test('different keys are not equal', () {
      expect(const QueryKey(['todos']), isNot(const QueryKey(['posts'])));
      expect(const QueryKey(['todos']), isNot(const QueryKey(['todos', 1])));
    });

    test('nested lists compare by value', () {
      expect(
        const QueryKey([
          'todos',
          ['a', 'b'],
        ]),
        const QueryKey([
          'todos',
          ['a', 'b'],
        ]),
      );
      expect(
        const QueryKey([
          'todos',
          ['a', 'b'],
        ]),
        isNot(
          const QueryKey([
            'todos',
            ['b', 'a'],
          ]),
        ),
      );
    });

    // Upstream sorts object keys before hashing so property order cannot
    // change a key's identity; DeepCollectionEquality gives us the same.
    test('map parts compare order-insensitively', () {
      expect(
        const QueryKey([
          'todos',
          {'status': 'open', 'page': 1},
        ]),
        const QueryKey([
          'todos',
          {'page': 1, 'status': 'open'},
        ]),
      );
      expect(
        const QueryKey([
          'todos',
          {'status': 'open', 'page': 1},
        ]).hashCode,
        const QueryKey([
          'todos',
          {'page': 1, 'status': 'open'},
        ]).hashCode,
      );
    });

    test('maps with different values are different keys', () {
      expect(
        const QueryKey([
          'todos',
          {'page': 1},
        ]),
        isNot(
          const QueryKey([
            'todos',
            {'page': 2},
          ]),
        ),
      );
    });

    test('works as a map key', () {
      final cache = <QueryKey, String>{};
      cache[const QueryKey(['todos', 1])] = 'first';
      cache[const QueryKey(['todos', 1])] = 'second';

      expect(cache, hasLength(1));
      expect(cache[const QueryKey(['todos', 1])], 'second');
    });
  });

  group('QueryKey.isPrefixOf', () {
    test('matches an identical key', () {
      expect(
        const QueryKey(['todos']).isPrefixOf(const QueryKey(['todos'])),
        isTrue,
      );
    });

    test('matches a longer key that starts with it', () {
      expect(
        const QueryKey(['todos']).isPrefixOf(const QueryKey(['todos', 1])),
        isTrue,
      );
      expect(
        const QueryKey([
          'todos',
        ]).isPrefixOf(const QueryKey(['todos', 'detail', 1])),
        isTrue,
      );
    });

    test('does not match a shorter or diverging key', () {
      expect(
        const QueryKey(['todos', 1]).isPrefixOf(const QueryKey(['todos'])),
        isFalse,
      );
      expect(
        const QueryKey(['todos']).isPrefixOf(const QueryKey(['posts', 1])),
        isFalse,
      );
    });

    test('matches a map part partially', () {
      // The filter declares one entry; the query key carries two.
      expect(
        const QueryKey([
          'todos',
          {'status': 'open'},
        ]).isPrefixOf(
          const QueryKey([
            'todos',
            {'status': 'open', 'page': 1},
          ]),
        ),
        isTrue,
      );
    });

    test('does not match when a declared map entry differs', () {
      expect(
        const QueryKey([
          'todos',
          {'status': 'done'},
        ]).isPrefixOf(
          const QueryKey([
            'todos',
            {'status': 'open', 'page': 1},
          ]),
        ),
        isFalse,
      );
    });

    test('does not match when a declared map entry is absent', () {
      expect(
        const QueryKey([
          'todos',
          {'archived': true},
        ]).isPrefixOf(
          const QueryKey([
            'todos',
            {'status': 'open'},
          ]),
        ),
        isFalse,
      );
    });

    test('an empty key matches everything', () {
      expect(
        const QueryKey([]).isPrefixOf(const QueryKey(['todos', 1])),
        isTrue,
      );
    });

    test('matches nested list parts by prefix', () {
      expect(
        const QueryKey([
          'todos',
          ['a'],
        ]).isPrefixOf(
          const QueryKey([
            'todos',
            ['a', 'b'],
          ]),
        ),
        isTrue,
      );
    });
  });
}
