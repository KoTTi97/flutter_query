/// `guides/pure-dart.md`'s samples — and the proof of the page's premise.
///
/// Its own file, and the only one here that does **not** import Flutter, so
/// the analyzer is what shows that the pure-Dart surface really is usable
/// without it. The samples print, which is what a console program does, so
/// `avoid_print` is off for this file alone rather than the page being
/// rewritten around `debugPrint` — a `package:flutter/foundation.dart`
/// function, on a page about not having Flutter.
///
/// Only the parts that need no `dart:io`; the page says which those are.
// ignore_for_file: avoid_print
library;

import 'package:query_kit/query_kit.dart';

import 'doc_snippets.dart' show Task, api;

final QueryKey _tasksKey = QueryKey(<Object?>['tasks']);

QueryKey _taskKey(String id) => QueryKey(<Object?>['tasks', id]);

/// The imperative read: no observer, no widget, one future.
Future<List<Task>> fetchWithoutFlutter() async {
  // >>> guides/pure-dart.md#imperative
  final client = QueryClient();
  client.mount();

  final tasks = await client.query<List<Task>>(
    QueryOptions<List<Task>>(
      queryKey: QueryKey(<Object?>['tasks']),
      queryFn: (context) => api.listTasks(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 45)),
    ),
  );
  // <<<
  client.clear();
  return tasks;
}

/// The reactive read: an observer and a subscription, which is what the
/// Flutter binding is built out of.
void Function() observeWithoutFlutter(QueryClient client, String id) {
  // >>> guides/pure-dart.md#observe
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
  return unsubscribe;
}

/// Keeps the private key helpers honest: they are the shape the page's prose
/// talks about, and an unused one would be a lie by omission.
List<QueryKey> keysThePageMentions(String id) =>
    <QueryKey>[_tasksKey, _taskKey(id)];
