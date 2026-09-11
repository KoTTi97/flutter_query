// A one-file tour: a provider, a query read three ways, and a mutation that
// invalidates it. No server — the "API" is a delay and a list.
//
//   flutter run
import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

/// Stands in for an HTTP client.
class Api {
  final List<String> _tasks = ['Küche', 'Flur', 'Garage'];

  Future<List<String>> list() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return List.unmodifiable(_tasks);
  }

  Future<void> add(String name) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _tasks.add(name);
  }
}

final api = Api();
final tasksKey = QueryKey(<Object?>['tasks']);

Future<List<String>> fetchTasks(QueryFunctionContext context) => api.list();

QueryObserverOptions<List<String>> tasksQuery() => QueryObserverOptions(
      queryKey: tasksKey,
      queryFn: fetchTasks,
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );

/// The same entry, reduced to one flag — a `select` shares the cache entry
/// and only rebuilds its reader when the selected value changes.
QuerySelectOptions<List<String>, bool> fetchingQuery() => QuerySelectOptions(
      queryKey: tasksKey,
      queryFn: fetchTasks,
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
      select: (_) => true,
    );

void main() {
  runApp(
    QueryClientProvider(
      client: QueryClient(),
      child: const MaterialApp(home: TasksScreen()),
    ),
  );
}

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Style 1: read in build. The widget rebuilds when the result changes.
    final tasks = context.query(tasksQuery());
    // The client, taken here in `build` rather than inside the callback
    // below. A mutation outlives the widget that started it — disposing its
    // controller does not cancel it — so `onSuccess` can run after this
    // element is gone, and looking an ancestor up from a deactivated element
    // throws. The cache work has to happen either way; the client is the
    // right thing to close over, the `BuildContext` is not.
    final client = QueryClientProvider.of(context);
    // A mutation, the same way. `MutationOptions.simple` is the form without
    // an `onMutate` step: its types come from `api.add`.
    final add = context.mutation(
      MutationOptions.simple(
        mutationFn: api.add,
        onSuccess: (_, __, ___) => client.invalidateQueries(
          filters: QueryFilters(queryKey: tasksKey),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasken'),
        actions: <Widget>[
          // Style 2: a builder, for a leaf that only wants one flag.
          QuerySelectBuilder<List<String>, bool>(
            options: fetchingQuery(),
            builder: (context, result) => result.isFetching
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => result.refetch(),
                  ),
          ),
        ],
      ),
      body: switch (tasks) {
        QueryPending() => const Center(child: CircularProgressIndicator()),
        QueryError(:final error, staleData: null) =>
          Center(child: Text('$error')),
        QuerySuccess(:final data) ||
        QueryError(staleData: final data!) =>
          ListView(
            children: <Widget>[
              for (final name in data) ListTile(title: Text(name)),
            ],
          ),
      },
      floatingActionButton: FloatingActionButton(
        onPressed: add.value.isPending
            ? null
            : () => add.mutate('Task ${DateTime.now().second}'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
