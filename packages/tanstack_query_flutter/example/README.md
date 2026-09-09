# tanstack_query_flutter examples

The full example is the sensor manager under
[`examples/sensor_demo/`](https://github.com/KoTTi97/flutter_query/tree/main/examples/sensor_demo)
in the repository: the React demo rebuilt on this binding, against the same
gateway and cache policy, with a widget test per row of its acceptance
checklist. What follows is the shape of each call style, taken from the
package README.

## Setting up

```dart
final client = QueryClient();

runApp(
  QueryClientProvider(
    client: client,
    child: const MyApp(),
  ),
);
```

## Four equal ways to read a query

There is no recommended default; pick per situation.

### `context.query(...)`

```dart
class SensorScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sensor = context.query(sensorQuery(id));
    return switch (sensor) {
      QueryPending() => const CircularProgressIndicator(),
      QuerySuccess(:final data) => SensorCard(data),
      QueryError(:final error) => ErrorBanner(error),
    };
  }
}
```

### `QueryBuilder`

```dart
QueryBuilder<Sensor>(
  options: sensorQuery(id),
  builder: (context, result) => switch (result) { … },
)
```

### `QueryMixin`

```dart
class _SensorScreenState extends State<SensorScreen> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final sensor = watchQuery(sensorQuery(widget.id));
    final rename = watchMutation(renameSensor());
    …
  }
}
```

### `QueryController`

```dart
final sensor = QueryController<Sensor, Sensor>(client, sensorQuery(id));
// … sensor.value, sensor.addListener, sensor.refetch() …
sensor.dispose();
```

## Infinite queries and mutations

The same four shapes: `context.infiniteQuery` / `watchInfiniteQuery` /
`InfiniteQueryBuilder` / `InfiniteQueryController`, and `context.mutation` /
`watchMutation` / `MutationBuilder` / `MutationController`.

```dart
final feed = context.infiniteQuery(feedQuery());
final pages = feed.value.dataOrNull?.pages ?? const [];
if (feed.hasNextPage) feed.fetchNextPage();
```
