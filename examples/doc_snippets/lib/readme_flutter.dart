/// `packages/query_kit_flutter/README.md`'s samples — the binding's pub.dev
/// landing page, frozen into every published archive, so it has to compile on
/// the day it ships.
///
/// The README's quick start owns its samples rather than naming the site's
/// twins: the site's pages move and are rewritten, and a landing page that
/// ships in an archive should not break when they do. The one exception is
/// the widget-test teardown, which the README shows exactly as the testing
/// guide does and which has to *run* (`test/teardown_snippet_test.dart`).
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'doc_snippets.dart' show MyApp, Task, api;

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

// >>> packages/query_kit_flutter/README.md#query-options
QueryObserverOptions<List<Task>> tasksQuery() => QueryObserverOptions(
      queryKey: QueryKey(<Object?>['tasks']),
      queryFn: (context) => api.listTasks(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );
// <<<

// >>> packages/query_kit_flutter/README.md#first-query
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.query(tasksQuery());

    return switch (tasks) {
      QueryPending() => const Center(child: CircularProgressIndicator()),
      QueryError(:final error) => Center(child: Text('$error')),
      QuerySuccess(:final data) => ListView(
          children: [for (final task in data) Text(task.name)],
        ),
    };
  }
}
// <<<

/// The same query in the other three call styles.
Widget readmeBuilder() =>
    // >>> packages/query_kit_flutter/README.md#builder
    QueryBuilder<List<Task>>(
      options: tasksQuery(),
      builder: (context, result) => switch (result) {
        QueryPending() => const Center(child: CircularProgressIndicator()),
        QueryError(:final error) => Center(child: Text('$error')),
        QuerySuccess(:final data) => ListView(
            children: [for (final task in data) Text(task.name)],
          ),
      },
    );
// <<<

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

// >>> packages/query_kit_flutter/README.md#mixin
class _TasksPageState extends State<TasksPage> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final tasks = watchQuery(tasksQuery());

    return Text('${tasks.dataOrNull?.length ?? 0} tasks');
  }
}
// <<<

void readmeController(QueryClient client) {
  // >>> packages/query_kit_flutter/README.md#controller
  final tasks = QueryController.create(client, tasksQuery());
  // … tasks.value, tasks.addListener, tasks.refetch() …
  tasks.dispose();
  // <<<
}

class AddTaskButton extends StatelessWidget {
  const AddTaskButton({super.key});

  // >>> packages/query_kit_flutter/README.md#first-mutation
  @override
  Widget build(BuildContext context) {
    // Take the client in build, not in the callback: a mutation can outlive
    // the widget that started it.
    final client = QueryClientProvider.of(context);

    final add = context.mutation(
      MutationOptions.simple(
        mutationFn: api.addTask,
        // Mark the list stale; everyone reading it refetches.
        onSuccess: (_, __, ___) => client.invalidateQueries(
          filters: QueryFilters(queryKey: QueryKey(<Object?>['tasks'])),
        ),
      ),
    );

    return FilledButton(
      onPressed: add.value.isPending ? null : () => add.mutate('New task'),
      child: Text(add.value.isPending ? 'Adding…' : 'Add'),
    );
  }
  // <<<
}
