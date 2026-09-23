/// `packages/query_kit_flutter/README.md`'s samples that the site does not
/// already show — the binding's pub.dev landing page, frozen into every
/// published archive (REL-8, release review 2026-09-23). The README's other
/// fences name the site's twins in `doc_snippets.dart` directly.
///
/// A list rather than one function per sample where the page shows a bare
/// widget *expression*, as `lifecycleProviders` does: a list element is the
/// one place a bare expression is also valid Dart.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'doc_snippets.dart';

/// The mutation without an optimistic step.
MutationController<void, String, void> readmeSimpleMutation(
  BuildContext context,
  QueryClient client,
) {
  // >>> packages/query_kit_flutter/README.md#mutation-simple
  final add = context.mutation(MutationOptions.simple(
    mutationFn: api.addTask,
    onSuccess: (_, __, ___) => client.invalidateQueries(
      filters: QueryFilters(queryKey: tasksKey),
    ),
  ));
  // <<<
  return add;
}

/// The widgets the README shows as expressions.
List<Widget> readmeWidgets(
  QueryController<Task, Task> task,
  List<String> visibleIds,
) =>
    <Widget>[
      // >>> packages/query_kit_flutter/README.md#listener
      QueryListener<Task, Task>(
        controller: task,
        listenWhen: (previous, next) =>
            previous.errorOrNull != next.errorOrNull,
        listener: (context, result) => ScaffoldMessenger.of(context)
            .showSnackBar(
                const SnackBar(content: Text('Could not load the task'))),
        child: const TasksScreen(),
      ),
      // <<<
      // >>> packages/query_kit_flutter/README.md#queries-builder
      QueriesBuilder<Task, String>(
        queries: [
          for (final id in visibleIds)
            QuerySelectOptions<Task, String>(
              queryKey: QueryKey(<Object?>['tasks', id]),
              queryFn: (context) => api.getTask(id, signal: context.signal),
              select: (task) => task.name,
            ),
        ],
        builder: (context, results) => Column(children: [
          for (final result in results) Text(result.dataOrNull ?? '…'),
        ]),
      ),
      // <<<
      // >>> packages/query_kit_flutter/README.md#provider-create
      QueryClientProvider.create(
        create: QueryClient.new,
        child: const MyApp(),
      ),
      // <<<
    ];

/// One client, above everything that reads it.
void readmeSetup() {
  // >>> packages/query_kit_flutter/README.md#setup
  final client = QueryClient();

  runApp(
    QueryClientProvider(
      client: client,
      child: const MyApp(),
    ),
  );
  // <<<
}
