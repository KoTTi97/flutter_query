// A pure-Dart tour of the core: one imperative fetch, one observer, a cache
// write, an invalidation, and the cleanup that lets the process exit.
//
//   dart run example/example.dart
import 'dart:async';

import 'package:tanstack_query_core/tanstack_query_core.dart';

/// A stand-in for an HTTP client.
class SensorApi {
  int calls = 0;

  Future<List<String>> listSensors() async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return const ['kitchen', 'hallway', 'garage'];
  }
}

final api = SensorApi();

final sensorsKey = QueryKey(<Object?>['sensors']);

Future<List<String>> fetchSensors(QueryFunctionContext context) =>
    api.listSensors();

QueryOptions<List<String>> sensorsQuery() => QueryOptions<List<String>>(
      queryKey: sensorsKey,
      queryFn: fetchSensors,
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );

Future<void> main() async {
  final client = QueryClient();
  // Mounted, the client reacts to focus and connectivity: refetch on focus
  // and reconnect, and paused mutations resume when the network is back. In
  // pure Dart you drive the managers yourself (`client.onlineManager
  // .setOnline(false)` and back); the Flutter binding wires them to the app.
  client.mount();

  // Imperative: fetch, cache, and complete with the data.
  final sensors = await client.query(sensorsQuery());
  print('fetched ${sensors.length} sensors (api calls: ${api.calls})');

  // Fresh data is served from the cache: no second call.
  await client.query(sensorsQuery());
  print('again from cache (api calls: ${api.calls})');

  // Reactive: an observer reports every change under its key as a sealed
  // result, so the switch is exhaustive and the data needs no `!`.
  final observer = client.observe<List<String>, int>(
    QueryObserverOptions<List<String>, int>(
      queryKey: sensorsKey,
      queryFn: fetchSensors,
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
      select: (names) => names.length,
    ),
  );
  void report(QueryResult<int> result) {
    switch (result) {
      case QueryPending():
        print('observer: loading');
      case QuerySuccess(:final data, :final isFetching):
        print('observer: $data sensors${isFetching ? ' (refetching)' : ''}');
      case QueryError(:final error, :final staleData):
        print('observer: $error (still showing $staleData)');
    }
  }

  // Subscribing reports changes from here on; the current result is a read.
  report(observer.currentResult);
  final unsubscribe = observer.subscribe(report);

  // A cache write reaches every observer of that key.
  client.updateQueryData<List<String>>(
    sensorsKey,
    (previous) => [...?previous, 'attic'],
  );

  // Invalidating marks the entry stale and refetches it for its observers.
  await client.invalidateQueries(
    filters: QueryFilters(queryKey: sensorsKey),
  );
  print('after invalidation (api calls: ${api.calls})');

  // A client owns gcTime timers and, mounted, the manager subscriptions;
  // release both so the program can exit.
  unsubscribe();
  client.unmount();
  client.clear();
}
