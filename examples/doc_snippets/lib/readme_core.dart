/// `packages/query_kit/README.md`'s sample — the pub.dev landing page of the
/// core, which is frozen into every published archive and so has to compile
/// on the day it ships (REL-8, release review 2026-09-23).
///
/// Its own file, and like `pure_dart.dart` without Flutter, because the page
/// is the core's. The sample prints, which is what a console program does.
// ignore_for_file: avoid_print
library;

import 'package:query_kit/query_kit.dart';

import 'doc_snippets.dart' show Task, api;

/// The README's first query: both halves, as one sample.
Future<void Function()> readmeFirstQuery(String id) async {
  // >>> packages/query_kit/README.md#first-query
  final client = QueryClient();

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
  return unsubscribe;
}
