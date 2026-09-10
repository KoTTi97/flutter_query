/// Port of `query-core/src/__tests__/infiniteQueryBehavior.test.tsx` at
/// upstream `50680b98c`. Omissions and adaptations: `test/PORTING_NOTES.md`.
library;

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

typedef IntPages = InfiniteData<int, int>;

void main() {
  group('InfiniteQueryBehavior', () {
    late QueryClient queryClient;

    setUp(() {
      queryClient = testClient();
      queryClient.mount();
    });

    tearDown(() => queryClient.clear());

    testFakeAsync(
        'should apply the maxPages option to limit the number of pages',
        (time) async {
      final key = queryKey();
      final calls = <(int, FetchDirection)>[];

      final observer = InfiniteQueryObserver<int, int, IntPages>(
        queryClient,
        InfiniteQueryObserverOptions<int, int, IntPages>(
          queryKey: key,
          pageFn: (context) {
            calls.add((context.pageParam, context.direction));
            return context.pageParam;
          },
          getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
          getPreviousPageParam: (firstPage, _, __, ___) => firstPage - 1,
          maxPages: 2,
          initialPageParam: 1,
        ),
      );

      QueryResult<IntPages>? observerResult;
      final unsubscribe = observer.subscribe((result) {
        observerResult = result;
      });

      // Wait for the first page to be fetched
      await time.flushMicrotasks();
      expect(observerResult!.isFetching, isFalse);
      expect(observerResult!.dataOrNull,
          const IntPages(pages: <int>[1], pageParams: <int>[1]));
      expect(calls, [(1, FetchDirection.forward)]);
      calls.clear();

      // Fetch the second page
      await observer.fetchNextPage();

      expect(calls, [(2, FetchDirection.forward)]);
      expect(observerResult!.isFetching, isFalse);
      expect(observerResult!.dataOrNull,
          const IntPages(pages: <int>[1, 2], pageParams: <int>[1, 2]));
      calls.clear();

      // Fetch the page before the first page
      await observer.fetchPreviousPage();

      expect(calls, [(0, FetchDirection.backward)]);
      // Only the first two pages are kept
      expect(observerResult!.dataOrNull,
          const IntPages(pages: <int>[0, 1], pageParams: <int>[0, 1]));
      calls.clear();

      // Fetch the page before that
      await observer.fetchPreviousPage();

      expect(calls, [(-1, FetchDirection.backward)]);
      expect(observerResult!.dataOrNull,
          const IntPages(pages: <int>[-1, 0], pageParams: <int>[-1, 0]));
      calls.clear();

      // Fetch the page after
      await observer.fetchNextPage();

      expect(calls, [(1, FetchDirection.forward)]);
      expect(observerResult!.dataOrNull,
          const IntPages(pages: <int>[0, 1], pageParams: <int>[0, 1]));
      calls.clear();

      // Refetch the infinite query: only two pages refetch
      await observer.refetch();

      expect(calls, [
        (0, FetchDirection.forward),
        (1, FetchDirection.forward),
      ]);

      unsubscribe();
    });

    testFakeAsync('should support query cancellation', (time) async {
      final key = queryKey();
      final calls = <int>[];

      final observer = InfiniteQueryObserver<int, int, IntPages>(
        queryClient,
        InfiniteQueryObserverOptions<int, int, IntPages>(
          queryKey: key,
          pageFn: (context) async {
            calls.add(context.pageParam);
            context.signal;
            await sleep(ms(10));
            return context.pageParam;
          },
          getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
          getPreviousPageParam: (firstPage, _, __, ___) => firstPage - 1,
          initialPageParam: 1,
        ),
      );

      QueryResult<IntPages>? observerResult;
      final unsubscribe = observer.subscribe((result) {
        observerResult = result;
      });

      observer.currentQuery.cancel().ignore();

      // Wait for the first page to be cancelled
      await time.flushMicrotasks();
      expect(observerResult!.isFetching, isFalse);
      expect(observerResult!.isError, isTrue);
      expect((observerResult! as QueryError<IntPages>).error,
          isA<CancelledError>());
      expect(observerResult!.dataOrNull, isNull);

      expect(calls, <int>[1]);

      unsubscribe();
      await time.advance(ms(10));
    });

    testFakeAsync('should not refetch pages if the query is cancelled',
        (time) async {
      final key = queryKey();
      var slow = false;
      final calls = <int>[];

      final observer = InfiniteQueryObserver<int, int, IntPages>(
        queryClient,
        InfiniteQueryObserverOptions<int, int, IntPages>(
          queryKey: key,
          pageFn: (context) async {
            calls.add(context.pageParam);
            context.signal;
            if (slow) {
              await sleep(ms(10));
            }
            return context.pageParam;
          },
          getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
          getPreviousPageParam: (firstPage, _, __, ___) => firstPage - 1,
          initialPageParam: 1,
        ),
      );

      QueryResult<IntPages>? observerResult;
      final unsubscribe = observer.subscribe((result) {
        observerResult = result;
      });

      // Wait for the first page to be fetched
      await time.flushMicrotasks();
      expect(observerResult!.dataOrNull,
          const IntPages(pages: <int>[1], pageParams: <int>[1]));

      // Fetch the second page
      await observer.fetchNextPage();
      expect(observerResult!.dataOrNull,
          const IntPages(pages: <int>[1, 2], pageParams: <int>[1, 2]));
      calls.clear();
      slow = true;

      // Refetch the query, then cancel it
      observer.refetch().ignore();
      expect(observerResult!.isFetching, isTrue);
      expect(observerResult!.isError, isFalse);

      await observer.currentQuery.cancel();
      await time.advance(ms(10));

      expect(observerResult!.isFetching, isFalse);
      expect(observerResult!.isError, isTrue);
      expect((observerResult! as QueryError<IntPages>).error,
          isA<CancelledError>());
      expect(observerResult!.dataOrNull,
          const IntPages(pages: <int>[1, 2], pageParams: <int>[1, 2]));

      // The second page was never re-fetched: the loop stopped at the first.
      expect(calls, <int>[1]);

      unsubscribe();
    });

    testFakeAsync(
        'should surface the cancellation when it happens between refetched pages',
        (time) async {
      final key = queryKey();
      final calls = <int>[];

      final observer = InfiniteQueryObserver<int, int, IntPages>(
        queryClient,
        InfiniteQueryObserverOptions<int, int, IntPages>(
          queryKey: key,
          pageFn: (context) async {
            calls.add(context.pageParam);
            context.signal;
            return context.pageParam;
          },
          getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
          initialPageParam: 1,
        ),
      );

      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      await observer.fetchNextPage();
      expect(observer.currentResult.dataOrNull,
          const IntPages(pages: <int>[1, 2], pageParams: <int>[1, 2]));

      calls.clear();

      // Cancel from inside the first refetched page: the loop must not go on
      // to the second.
      final query = observer.currentQuery;
      final refetch = observer.refetch();
      query.cancel().ignore();
      await refetch;
      await time.flushMicrotasks();

      expect(calls, <int>[1]);
      expect(observer.currentResult.isError, isTrue);

      unsubscribe();
    });

    testFakeAsync(
        'should not enter an infinite loop when a page errors while retry is on '
        '#8046', (time) async {
      var errorCount = 0;
      final key = queryKey();

      Future<(List<String>, int?)> fetchData(int nextToken) async {
        await sleep(ms(10));
        if (nextToken == 2 && errorCount < 3) {
          errorCount += 1;
          throw StateError('429');
        }
        const fake = <(List<String>, int?)>[
          (<String>['item-1'], 1),
          (<String>['item-2'], 2),
          (<String>['item-3'], 3),
          (<String>['item-4'], null),
        ];
        return fake[nextToken];
      }

      final observer = InfiniteQueryObserver<(List<String>, int?), int,
          InfiniteData<(List<String>, int?), int>>(
        queryClient,
        InfiniteQueryObserverOptions<(List<String>, int?), int,
            InfiniteData<(List<String>, int?), int>>(
          retry: const RetryTimes(5),
          staleTime: StaleTime.zero,
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 10)),
          queryKey: key,
          initialPageParam: 1,
          getNextPageParam: (lastPage, _, __, ___) => lastPage.$2,
          pageFn: (context) => fetchData(context.pageParam),
        ),
      );

      // Fetch page 1
      final page1 = observer.fetchNextPage();
      await time.advance(ms(10));
      expect((await page1).dataOrNull?.pageParams, <int>[1]);

      // Fetch page 2 — the page function rejects three times, then resolves
      final page2 = observer.fetchNextPage();
      await time.advance(ms(70));
      expect((await page2).dataOrNull?.pageParams, <int>[1, 2]);

      // Fetch page 3
      final page3 = observer.fetchNextPage();
      await time.advance(ms(10));
      expect((await page3).dataOrNull?.pageParams, <int>[1, 2, 3]);

      // Re-fetching must not restart from page 1 every time it reaches the
      // page that errors.
      errorCount = 0;
      final refetched = observer.fetchNextPage();
      await time.advance(ms(10));
      expect((await refetched).dataOrNull?.pageParams, <int>[1, 2, 3]);
    });

    testFakeAsync('should fetch even if initialPageParam is null',
        (time) async {
      final key = queryKey();

      final observer =
          InfiniteQueryObserver<String, Object?, InfiniteData<String, Object?>>(
        queryClient,
        InfiniteQueryObserverOptions<String, Object?,
            InfiniteData<String, Object?>>(
          queryKey: key,
          pageFn: (_) => 'data',
          getNextPageParam: (_, __, ___, ____) => null,
          initialPageParam: null,
        ),
      );

      QueryResult<InfiniteData<String, Object?>>? observerResult;
      final unsubscribe = observer.subscribe((result) {
        observerResult = result;
      });

      await time.flushMicrotasks();
      expect(observerResult!.isFetching, isFalse);
      expect(
        observerResult!.dataOrNull,
        const InfiniteData<String, Object?>(
          pages: <String>['data'],
          pageParams: <Object?>[null],
        ),
      );

      unsubscribe();
    });

    testFakeAsync(
        'should not fetch next page when getNextPageParam returns null',
        (time) async {
      final key = queryKey();

      final observer = InfiniteQueryObserver<int, int, IntPages>(
        queryClient,
        InfiniteQueryObserverOptions<int, int, IntPages>(
          queryKey: key,
          pageFn: (context) async {
            await sleep(Duration.zero);
            return context.pageParam;
          },
          getNextPageParam: (lastPage, _, __, ___) =>
              lastPage == 1 ? null : lastPage + 1,
          initialPageParam: 1,
        ),
      );

      QueryResult<IntPages>? observerResult;
      final unsubscribe = observer.subscribe((result) {
        observerResult = result;
      });

      await time.flushMicrotasks();
      expect(observerResult!.isFetching, isFalse);
      expect(observerResult!.dataOrNull,
          const IntPages(pages: <int>[1], pageParams: <int>[1]));

      await observer.fetchNextPage();

      expect(observerResult!.isFetching, isFalse);
      expect(observerResult!.dataOrNull,
          const IntPages(pages: <int>[1], pageParams: <int>[1]));

      unsubscribe();
    });
  });
}
