/// Regressions from the first integration into a real app (BR64, 2026-09-19).
/// Port-only behaviour; PORTING_NOTES' "First real integration" section says
/// what each one was.
library;

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  // I1 — a partly equal list was rebuilt with `next.toList()`, which is
  // growable whatever `next` was: an unmodifiable list handed to
  // `setQueryData` came back out of the cache as one anybody could `add` to.
  group('I1 structural sharing keeps the incoming list\'s modifiability', () {
    test('a partly equal unmodifiable list stays unmodifiable in the cache',
        () {
      final client = testClient();
      final key = queryKey();
      client
        ..setQueryData<List<int>>(key, List<int>.unmodifiable(const [1, 2]))
        ..setQueryData<List<int>>(key, List<int>.unmodifiable(const [1, 3]));
      final data = client.getQueryData<List<int>>(key)!;
      expect(data, [1, 3]);
      expect(() => data.add(4), throwsUnsupportedError);
      expect(() => data[0] = 9, throwsUnsupportedError);
      client.clear();
    });

    test('an equal unmodifiable list is still shared whole', () {
      final previous = List<int>.unmodifiable(const [1, 2]);
      final next = List<int>.unmodifiable(const [1, 2]);
      expect(replaceEqualDeep<List<int>>(previous, next), same(previous));
    });

    // The trade, decided for identity: no unmodifiable list of `next`'s
    // runtime element type can be built inside the walk, so when a cached
    // instance is swapped in, the copy is fixed-length — `add` throws,
    // `[i] =` does not. Refetching sealed DTO lists keeps its instances.
    test(
        'an unmodifiable list with a part to share comes back fixed-length, '
        'typed, with the cached instance in it', () {
      final previous = List<List<int>>.unmodifiable([
        <int>[1],
        <int>[2]
      ]);
      const next = <List<int>>[
        <int>[1],
        <int>[3]
      ];
      final shared = replaceEqualDeep<List<List<int>>>(previous, next);
      expect(shared, isA<List<List<int>>>());
      expect(shared[0], same(previous[0]));
      expect(shared[1], [3]);
      expect(() => shared.add(<int>[4]), throwsUnsupportedError);
      expect(shared.removeLast, throwsUnsupportedError);
    });

    test('with nothing to swap in, a sealed list comes back as itself', () {
      final previous = List<int>.unmodifiable(const [1, 2]);
      final next = List<int>.unmodifiable(const [1, 3]);
      final shared = replaceEqualDeep<List<int>>(previous, next);
      expect(shared, same(next));
      expect(() => shared[0] = 9, throwsUnsupportedError);
    });

    test('a fixed-length list comes back fixed-length, its equal parts shared',
        () {
      final previous = <List<int>>[
        <int>[1],
        <int>[2]
      ];
      final next = List<List<int>>.of([
        <int>[1],
        <int>[3]
      ], growable: false);
      final shared = replaceEqualDeep<List<List<int>>>(previous, next);
      expect(shared, isNot(same(next)));
      expect(shared[0], same(previous[0]));
      expect(shared[1], [3]);
      expect(() => shared.add(<int>[4]), throwsUnsupportedError);
      shared[1] = <int>[5];
      expect(shared[1], [5]);
    });

    test('a growable list is still copied, growable, with its parts shared',
        () {
      final previous = <List<int>>[
        <int>[1],
        <int>[2]
      ];
      final next = <List<int>>[
        <int>[1],
        <int>[3]
      ];
      final shared = replaceEqualDeep<List<List<int>>>(previous, next);
      expect(shared, isNot(same(next)));
      expect(shared[0], same(previous[0]));
      shared.add(<int>[4]);
      expect(shared, hasLength(3));
      // The probe leaves the caller's list as it was.
      expect(next, [
        [1],
        [3]
      ]);
    });

    test('an empty unmodifiable list replacing a full one stays unmodifiable',
        () {
      final shared = replaceEqualDeep<List<int>>(
          <int>[1], List<int>.unmodifiable(const <int>[]));
      expect(shared, isEmpty);
      expect(() => shared.add(1), throwsUnsupportedError);
    });

    testFakeAsync(
        'an infinite refetch still shares its unchanged pages, and the '
        'pages list in the cache is sealed', (time) async {
      final client = testClient();
      final key = queryKey();
      var second = 1;
      final options = InfiniteQueryOptions<List<int>, int>(
        queryKey: key,
        initialPageParam: 0,
        getNextPageParam: (_, __, param, ___) => param < 1 ? param + 1 : null,
        pageFn: (context) async => [if (context.pageParam == 0) 0 else second],
        pages: 2,
      );
      await client.infiniteQuery<List<int>, int>(options);
      final before = client.getInfiniteQueryData<List<int>, int>(key)!;
      second = 7;
      await client.infiniteQuery<List<int>, int>(options);
      final after = client.getInfiniteQueryData<List<int>, int>(key)!;
      expect(after.pages, [
        [0],
        [7]
      ]);
      expect(after.pages[0], same(before.pages[0]));
      expect(after.pageParams, same(before.pageParams));
      expect(() => after.pages.add([99]), throwsUnsupportedError);
      client.clear();
    });
  });
}
