/// The guide pages' samples that have no home in `doc_snippets.dart`: the
/// concept pages written when the site was reorganised one concept per page.
///
/// Same rule as the rest of this package — each region is marked with the
/// page that shows it, and the fence on that page names the region.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'doc_snippets.dart';

// ---------------------------------------------------------------------------
// guides/queries.md
// ---------------------------------------------------------------------------

// >>> guides/queries.md#status
Widget taskTitle(QueryResult<Task> task) => switch (task) {
      QueryPending(isPaused: true) => const Text('Waiting for the network…'),
      QueryPending() => const Text('Loading…'),
      QueryError(:final staleData?) =>
        Text('${staleData.name} (not refreshed)'),
      QueryError(:final error) => Text('Could not load: $error'),
      QuerySuccess(:final data, isRefetching: true) => Text('${data.name} …'),
      QuerySuccess(:final data) => Text(data.name),
    };
// <<<

// ---------------------------------------------------------------------------
// guides/query-keys.md
// ---------------------------------------------------------------------------

// >>> guides/query-keys.md#key-factory
abstract final class TaskKeys {
  static final QueryKey all = QueryKey(<Object?>['tasks']);

  static QueryKey list({required String filter}) =>
      all.append(<Object?>['list', filter]);

  static QueryKey detail(String id) => all.append(<Object?>['detail', id]);
}
// <<<

// ---------------------------------------------------------------------------
// guides/disabling-queries.md
// ---------------------------------------------------------------------------

// >>> guides/disabling-queries.md#lazy
QueryObserverOptions<List<Task>> searchQuery(String needle) =>
    QueryObserverOptions(
      queryKey: TaskKeys.all.append(<Object?>['search', needle]),
      queryFn: (context) => api.search(needle, signal: context.signal),
      // Nothing typed yet: nothing to ask the server.
      enabled: needle.isEmpty ? Enabled.no : Enabled.yes,
    );
// <<<

// ---------------------------------------------------------------------------
// guides/background-fetching-indicators.md
// ---------------------------------------------------------------------------

// >>> guides/background-fetching-indicators.md#global-indicator
class FetchingBar extends StatefulWidget {
  const FetchingBar({super.key});

  @override
  State<FetchingBar> createState() => _FetchingBarState();
}

class _FetchingBarState extends State<FetchingBar> {
  late final IsFetchingController _fetching =
      IsFetchingController(QueryClientProvider.read(context));

  @override
  void dispose() {
    _fetching.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: _fetching,
        builder: (context, count, _) => count == 0
            ? const SizedBox(height: 2)
            : const LinearProgressIndicator(minHeight: 2),
      );
}
// <<<

// ---------------------------------------------------------------------------
// guides/query-invalidation.md
// ---------------------------------------------------------------------------

Future<void> invalidateAfterRename(QueryClient client, String id) async {
  // >>> guides/query-invalidation.md#invalidate
  // Every key that starts with ['tasks']: the lists and every detail.
  await client.invalidateQueries(
    filters: QueryFilters(queryKey: TaskKeys.all),
  );

  // This one detail only.
  await client.invalidateQueries(
    filters: QueryFilters(queryKey: TaskKeys.detail(id), exact: true),
  );

  // Mark everything under ['tasks'] stale, and refetch nothing now.
  await client.invalidateQueries(
    filters: QueryFilters(queryKey: TaskKeys.all),
    refetchType: RefetchType.none,
  );
  // <<<
}

// ---------------------------------------------------------------------------
// guides/global-callbacks.md
// ---------------------------------------------------------------------------

// >>> guides/global-callbacks.md#error-toasts
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

QueryClient clientWithErrorToasts() => QueryClient(
      queryCache: QueryCache(
        onError: (error, stackTrace, query) {
          // A first load shows its own error; only a failed background
          // refresh of data already on screen deserves a toast.
          if (!query.state.hasData) return;
          // A query can opt out through its meta.
          if (query.meta case {'silent': true}) return;
          messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Could not refresh: $error')),
          );
        },
      ),
      mutationCache: MutationCache(
        onError: (error, stackTrace, variables, onMutateResult, mutation) {
          messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Could not save: $error')),
          );
        },
      ),
    );
// <<<

// ---------------------------------------------------------------------------
// guides/debugging.md
// ---------------------------------------------------------------------------

// >>> guides/debugging.md#subscribe
void Function() logCacheEvents(QueryClient client) =>
    client.queryCache.subscribe((event) {
      final key = event.query.queryKey.debugString;
      switch (event) {
        case QueryAdded():
          debugPrint('added $key');
        case QueryRemoved():
          debugPrint('removed $key');
        case QueryUpdated():
          final state = event.query.state;
          debugPrint('$key: ${state.status} / ${state.fetchStatus}');
        default:
          break;
      }
    });
// <<<

// ---------------------------------------------------------------------------
// guides/testing.md
// ---------------------------------------------------------------------------

// >>> guides/testing.md#no-retries
QueryClient testClient() => QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(retry: RetryPolicy.never),
      ),
    );
// <<<

// ---------------------------------------------------------------------------
// guides/initial-query-data.md and guides/query-retries.md
// ---------------------------------------------------------------------------

// >>> guides/initial-query-data.md#seed-from-list
QueryObserverOptions<Task> taskSeededFromList(QueryClient client, String id) =>
    QueryObserverOptions(
      queryKey: taskKey(id),
      queryFn: (context) => api.getTask(id, signal: context.signal),
      initialData: InitialData.compute(
        () => client
            .getQueryData<List<Task>>(tasksKey)
            ?.where((task) => task.id == id)
            .firstOrNull,
      ),
      // As old as the list it came from.
      initialDataUpdatedAtCompute: () => client.queryCache
          .find(filters: QueryFilters(queryKey: tasksKey))
          ?.state
          .dataUpdatedAt,
    );
// <<<

/// An exception type of the app's own, carrying the status code.
class HttpError implements Exception {
  const HttpError(this.statusCode);

  final int statusCode;
}

// >>> guides/query-retries.md#retry-when
const RetryPolicy retryUnlessNotFound = RetryPolicy.when(_retryUnlessNotFound);

bool _retryUnlessNotFound(int failureCount, Object error, StackTrace _) =>
    failureCount < 3 && !(error is HttpError && error.statusCode == 404);
// <<<
