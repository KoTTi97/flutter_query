/// `packages/query_kit/README.md`'s samples — the pub.dev landing page of the
/// core, which is frozen into every published archive and so has to compile
/// on the day it ships.
///
/// Its own file, and like `pure_dart.dart` without Flutter, because the page
/// is the core's. The samples print, which is what a console program does.
// ignore_for_file: avoid_print
library;

import 'package:query_kit/query_kit.dart';

import 'doc_snippets.dart' show Task, api;

/// The README's quick start, top to bottom: setup, a first query read two
/// ways, a first mutation, and the cleanup that lets the process exit.
Future<void> readmeQuickStart(String id) async {
  // >>> packages/query_kit/README.md#setup
  final client = QueryClient();
  client.mount(); // react to focus and connectivity changes
  // <<<

  // >>> packages/query_kit/README.md#first-query
  // Imperative: fetch and cache, completing with the data.
  final tasks = await client.query<List<Task>>(
    QueryOptions<List<Task>>(
      queryKey: QueryKey(<Object?>['tasks']),
      queryFn: (context) => api.listTasks(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 45)),
    ),
  );

  // Reactive: an observer that keeps a widget (or anything) up to date.
  final observer = client.observe<Task, Task>(
    QueryObserverOptions<Task>(
      queryKey: QueryKey(<Object?>['tasks', id]),
      queryFn: (context) => api.getTask(id, signal: context.signal),
    ),
  );

  final unsubscribe = observer.subscribe((result) {
    switch (result) {
      case QueryPending():
        print('loading');
      case QuerySuccess(:final data):
        print(data.name);
      case QueryError(:final error, :final staleData):
        print('$error (still showing ${staleData?.name})');
    }
  });
  // <<<
  print(tasks.length);

  // >>> packages/query_kit/README.md#first-mutation
  final addTask = MutationObserver(
    client,
    MutationOptions.simple(
      mutationFn: api.addTask,
      // Mark the list stale and refetch it for whoever is watching.
      onSuccess: (_, __, ___) => client.invalidateQueries(
        filters: QueryFilters(queryKey: QueryKey(<Object?>['tasks'])),
      ),
    ),
  );

  await addTask.mutateAsync('Write the release notes');
  // <<<

  // >>> packages/query_kit/README.md#cleanup
  unsubscribe();
  client.unmount();
  client.clear(); // empties the cache and cancels its timers
  // <<<
}
