/// Port of `query-core/src/__tests__/infiniteQueryObserver.test.tsx` at
/// upstream `50680b98c`. Omissions and adaptations: `test/PORTING_NOTES.md`.
library;

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('InfiniteQueryObserver', () {
    late QueryClient queryClient;

    setUp(() {
      queryClient = testClient();
      queryClient.mount();
    });

    tearDown(() => queryClient.clear());

    testFakeAsync('should be able to fetch an infinite query with selector',
        (time) async {
      final key = queryKey();
      final observer =
          InfiniteQueryObserver<int, int, InfiniteData<String, int>>(
        queryClient,
        InfiniteQuerySelectOptions<int, int, InfiniteData<String, int>>(
          queryKey: key,
          pageFn: (_) async {
            await sleep(ms(10));
            return 1;
          },
          select: (data) => InfiniteData<String, int>(
            pages: data.pages.map((page) => '$page').toList(),
            pageParams: data.pageParams,
          ),
          initialPageParam: 1,
          getNextPageParam: (_, __, ___, ____) => 2,
        ),
      );
      QueryResult<InfiniteData<String, int>>? observerResult;
      final unsubscribe = observer.subscribe((result) {
        observerResult = result;
      });
      await time.advance(ms(10));
      unsubscribe();
      expect(
        observerResult!.dataOrNull,
        const InfiniteData<String, int>(
          pages: <String>['1'],
          pageParams: <int>[1],
        ),
      );
    });

    testFakeAsync('should pass the meta option to the page function',
        (time) async {
      const meta = <String, String>{'it': 'works'};

      final key = queryKey();
      final seen = <Object?>[];
      final observer =
          InfiniteQueryObserver<int, int, InfiniteData<String, int>>(
        queryClient,
        InfiniteQuerySelectOptions<int, int, InfiniteData<String, int>>(
          meta: meta,
          queryKey: key,
          pageFn: (context) async {
            seen.add(context.meta);
            await sleep(ms(10));
            return 1;
          },
          select: (data) => InfiniteData<String, int>(
            pages: data.pages.map((page) => '$page').toList(),
            pageParams: data.pageParams,
          ),
          initialPageParam: 1,
          getNextPageParam: (_, __, ___, ____) => 2,
        ),
      );
      QueryResult<InfiniteData<String, int>>? observerResult;
      final unsubscribe = observer.subscribe((result) {
        observerResult = result;
      });
      await time.advance(ms(10));
      unsubscribe();
      expect(
        observerResult!.dataOrNull,
        const InfiniteData<String, int>(
          pages: <String>['1'],
          pageParams: <int>[1],
        ),
      );
      expect(seen, [same(meta)]);
    });

    testFakeAsync(
        'should make getNextPageParam and getPreviousPageParam receive current '
        'pageParams', (time) async {
      final key = queryKey();
      var single = <String>[];
      var all = <String>[];
      final observer =
          InfiniteQueryObserver<String, int, InfiniteData<String, int>>(
        queryClient,
        InfiniteQueryObserverOptions<String, int>(
          queryKey: key,
          pageFn: (context) async {
            await sleep(ms(10));
            return '${context.pageParam}';
          },
          initialPageParam: 1,
          getNextPageParam: (_, __, lastPageParam, allPageParams) {
            single.add('next$lastPageParam');
            all.add('next${allPageParams.join(',')}');
            return lastPageParam + 1;
          },
          getPreviousPageParam: (_, __, firstPageParam, allPageParams) {
            single.add('prev$firstPageParam');
            all.add('prev${allPageParams.join(',')}');
            return firstPageParam - 1;
          },
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(10));

      // Upstream recomputes `hasNextPage`/`hasPreviousPage` while building
      // every result, so its expected sequence counts those calls too. Here
      // they are lazy getters on the observer, so the sequence records what the
      // *paging* actually asked for, plus the two explicit reads below.
      expect(observer.hasNextPage, isTrue);
      expect(observer.hasPreviousPage, isTrue);
      expect(single, <String>['next1', 'prev1']);
      expect(all, <String>['next1', 'prev1']);

      single = <String>[];
      all = <String>[];

      observer.fetchNextPage().ignore();
      await time.advance(ms(10));
      observer.fetchPreviousPage().ignore();
      await time.advance(ms(10));

      expect(single, <String>['next1', 'prev1']);
      expect(all, <String>['next1', 'prev1,2']);

      single = <String>[];
      all = <String>[];

      observer.refetch().ignore();
      await time.advance(ms(30));

      expect(single, <String>['next0', 'next1']);
      expect(all, <String>['next0', 'next0,1']);

      unsubscribe();
    });

    testFakeAsync(
        'should not invoke getNextPageParam and getPreviousPageParam on empty '
        'pages', (time) async {
      final key = queryKey();

      var nextCalls = 0;
      var previousCalls = 0;

      final observer =
          InfiniteQueryObserver<String, int, InfiniteData<String, int>>(
        queryClient,
        InfiniteQueryObserverOptions<String, int>(
          queryKey: key,
          pageFn: (context) async {
            await sleep(ms(10));
            return '${context.pageParam}';
          },
          initialPageParam: 1,
          getNextPageParam: (_, __, lastPageParam, ___) {
            nextCalls++;
            return lastPageParam + 1;
          },
          getPreviousPageParam: (_, __, firstPageParam, ___) {
            previousCalls++;
            return firstPageParam - 1;
          },
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      nextCalls = 0;
      previousCalls = 0;

      queryClient.setQueryData<InfiniteData<String, int>>(
        key,
        const InfiniteData<String, int>(pages: <String>[], pageParams: <int>[]),
      );

      expect(nextCalls, 0);
      expect(previousCalls, 0);

      unsubscribe();
      await time.advance(ms(10));
    });

    testFakeAsync(
        'should stop refetching if null is returned from getNextPageParam',
        (time) async {
      final key = queryKey();
      int? next = 2;
      var calls = 0;
      final observer =
          InfiniteQueryObserver<String, int, InfiniteData<String, int>>(
        queryClient,
        InfiniteQueryObserverOptions<String, int>(
          queryKey: key,
          pageFn: (context) async {
            calls++;
            await sleep(ms(10));
            return '${context.pageParam}';
          },
          initialPageParam: 1,
          getNextPageParam: (_, __, ___, ____) => next,
        ),
      );

      observer.fetchNextPage().ignore();
      await time.advance(ms(10));
      observer.fetchNextPage().ignore();
      await time.advance(ms(10));

      expect(observer.currentResult.dataOrNull?.pages, <String>['1', '2']);
      expect(calls, 2);
      expect(observer.hasNextPage, isTrue);

      next = null;

      observer.refetch().ignore();
      await time.advance(ms(10));

      expect(observer.currentResult.dataOrNull?.pages, <String>['1']);
      expect(calls, 3);
      expect(observer.hasNextPage, isFalse);
    });

    testFakeAsync(
        'should set infinite query behavior via getOptimisticResult and return '
        'the initial state', (time) async {
      final key = queryKey();
      final options = InfiniteQueryObserverOptions<int, int>(
        queryKey: key,
        pageFn: (_) async {
          await sleep(ms(10));
          return 1;
        },
        initialPageParam: 1,
        getNextPageParam: (_, __, ___, ____) => 2,
        refetchOnReconnect: RefetchOn.never,
      );
      final observer = InfiniteQueryObserver<int, int, InfiniteData<int, int>>(
        queryClient,
        options,
      );

      final result = observer.getOptimisticInfiniteResult(options);

      expect(result.status, QueryStatus.pending);
      expect(result.fetchStatus, FetchStatus.fetching);
      expect(result.dataOrNull, isNull);
      expect(observer.hasNextPage, isFalse);
      expect(observer.hasPreviousPage, isFalse);
      expect(observer.isFetchingNextPage, isFalse);
      expect(observer.isFetchingPreviousPage, isFalse);
    });
  });
}
