/// The site's landing page sample (`website/src/pages/index.tsx`).
///
/// The landing page is a React page, not Markdown, so its sample carries no
/// fence for `site_fences_test.dart` to read. It is held to the same rule by
/// its own check instead: `test/landing_sample_test.dart` compares the
/// region between the `landing:` markers below with the `sample` string in
/// `index.tsx`, character for character. The markers differ from the
/// `>>>`/`<<<` pair on purpose, so the fence check does not count this region
/// as an orphan.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'doc_snippets.dart' show Task, api;

// landing: start
QueryObserverOptions<List<Task>> tasksQuery() => QueryObserverOptions(
      queryKey: QueryKey(<Object?>['tasks']),
      queryFn: (context) => api.listTasks(signal: context.signal),
    );

class TaskList extends StatelessWidget {
  const TaskList({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.query(tasksQuery());

    return switch (tasks) {
      QueryPending() => const CircularProgressIndicator(),
      QueryError(:final error) => Text('Could not load: $error'),
      QuerySuccess(:final data) => ListView(
          children: <Widget>[
            for (final task in data) Text(task.name),
          ],
        ),
    };
  }
}
// landing: end
