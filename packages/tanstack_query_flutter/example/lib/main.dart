// A one-file tour: a provider, a query read three ways, and a mutation that
// invalidates it. No server — the "API" is a delay and a list.
//
//   flutter run
import 'package:flutter/material.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

/// Stands in for an HTTP client.
class Api {
  final List<String> _sensors = ['Küche', 'Flur', 'Garage'];

  Future<List<String>> list() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return List.unmodifiable(_sensors);
  }

  Future<void> add(String name) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _sensors.add(name);
  }
}

final api = Api();
final sensorsKey = QueryKey(<Object?>['sensors']);

Future<List<String>> fetchSensors(QueryFunctionContext context) => api.list();

QueryObserverOptions<List<String>, List<String>> sensorsQuery() =>
    QueryObserverOptions(
      queryKey: sensorsKey,
      queryFn: fetchSensors,
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );

/// The same entry, reduced to one flag — a `select` shares the cache entry
/// and only rebuilds its reader when the selected value changes.
QueryObserverOptions<List<String>, bool> fetchingQuery() =>
    QueryObserverOptions(
      queryKey: sensorsKey,
      queryFn: fetchSensors,
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
      select: (_) => true,
    );

void main() {
  runApp(
    QueryClientProvider(
      client: QueryClient(),
      child: const MaterialApp(home: SensorsScreen()),
    ),
  );
}

class SensorsScreen extends StatelessWidget {
  const SensorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Style 1: read in build. The widget rebuilds when the result changes.
    final sensors = context.query(sensorsQuery());
    // A mutation, the same way; `void` is what `onMutate` would return.
    final add = context.mutation(
      MutationOptions<void, String, void>(
        mutationFn: api.add,
        onSuccess: (_, __, ___) =>
            QueryClientProvider.read(context).invalidateQueries(
          filters: QueryFilters(queryKey: sensorsKey),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensoren'),
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
      body: switch (sensors) {
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
            : () => add.mutate('Sensor ${DateTime.now().second}'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
