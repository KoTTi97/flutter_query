/// The overview: search, room filter, refresh, create, delete — and the rows.
///
/// Two of the binding's four styles earn their place here:
///
/// * the screen holds a **`QueryController`** for the list, because the toolbar
///   and the body are siblings that both need it (refresh disabled while
///   fetching, error banner, the rows). One controller and two small
///   `ListenableBuilder`s beat one builder wrapping the whole screen.
/// * each row uses **`context.query`**, because rows read *different* keys and
///   that style rebuilds only the row whose sensor changed.
library;

import 'package:flutter/material.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

import '../api.dart';
import '../app_state.dart';
import '../models.dart';
import '../queries.dart';

const List<String> rooms = <String>[
  'all',
  'Wohnzimmer',
  'Küche',
  'Schlafzimmer',
  'Bad',
  'Flur',
];

class SensorOverview extends StatefulWidget {
  const SensorOverview({super.key, required this.api});

  final SensorApi api;

  @override
  State<SensorOverview> createState() => _SensorOverviewState();
}

class _SensorOverviewState extends State<SensorOverview> {
  QueryController<SensorListResponse, SensorListResponse>? _list;
  SensorFilters? _filters;
  final TextEditingController _search = TextEditingController();

  QueryClient get _client => QueryClientProvider.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final filters = AppScope.of(context).filters;
    final options = sensorListQuery(_client, widget.api, filters);
    if (_list == null) {
      _list = QueryController<SensorListResponse, SensorListResponse>(
        _client,
        options,
      );
    } else if (filters != _filters) {
      // A changed filter re-keys the list. The observer switches queries in
      // place; the previous entry stays cached and is garbage-collected on its
      // own schedule.
      _list!.setOptions(options);
    }
    _filters = filters;
  }

  @override
  void dispose() {
    _list?.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (_search.text != app.search) {
      _search.text = app.search;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: app.setSearch,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'Sensoren durchsuchen…',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: app.room,
                onChanged: (room) => app.setRoom(room ?? 'all'),
                items: <DropdownMenuItem<String>>[
                  for (final room in rooms)
                    DropdownMenuItem<String>(
                      value: room,
                      child: Text(room == 'all' ? 'Alle Räume' : room),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              // The refresh button needs `isFetching` from the same query the
              // body renders — the reason the controller sits on the State.
              ListenableBuilder(
                listenable: _list!,
                builder: (context, _) => IconButton(
                  tooltip: 'Neu laden',
                  onPressed:
                      _list!.value.isFetching ? null : () => _list!.refetch(),
                  icon: _list!.value.isFetching
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ),
              _CreateSensorButton(api: widget.api),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: _list!,
            builder: (context, _) => switch (_list!.value) {
              // The skeleton is only for the first load: a later refetch keeps
              // the rows on screen and shows the quiet spinner in the toolbar.
              // That is `status` and `fetchStatus` being different questions.
              QueryPending() => const _ListSkeleton(),
              QueryError(:final error, staleData: null) =>
                _ErrorPanel(error: error, onRetry: () => _list!.refetch()),
              QuerySuccess(:final data) ||
              QueryError(staleData: final data!) =>
                _SensorList(sensors: data.sensors, api: widget.api),
            },
          ),
        ),
      ],
    );
  }
}

class _SensorList extends StatelessWidget {
  const _SensorList({required this.sensors, required this.api});

  final List<Sensor> sensors;
  final SensorApi api;

  @override
  Widget build(BuildContext context) {
    if (sensors.isEmpty) {
      return const Center(child: Text('Keine Sensoren gefunden.'));
    }
    return MutationBuilder<String, String, ListSnapshot>(
      options: deleteSensorMutation(QueryClientProvider.of(context), api),
      builder: (context, delete) => Column(
        children: <Widget>[
          if (delete.value case MutationError(:final error))
            _Banner(text: '$error'),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: sensors.length,
              itemBuilder: (context, index) => SensorRow(
                key: ValueKey<String>(sensors[index].id),
                id: sensors[index].id,
                api: api,
                onDelete: () => delete.mutate(sensors[index].id),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row.
///
/// Subscribes to the same per-sensor query the detail screen uses, so a rename
/// invalidating that one key updates this row too — no list refetch, and
/// nothing to wire between the two screens.
class SensorRow extends StatelessWidget {
  const SensorRow({
    super.key,
    required this.id,
    required this.api,
    required this.onDelete,
  });

  final String id;
  final SensorApi api;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final sensor = context.query(sensorQuery(client, api, id)).dataOrNull;
    if (sensor == null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: () => AppScope.of(context).openSensor(id),
        title: Text(sensor.name),
        subtitle: Text(
          '${sensor.type.label} · ${sensor.room} · ${sensor.battery} % Batterie',
        ),
        leading: Icon(
          switch (sensor.type) {
            SensorType.contact => Icons.sensor_door_outlined,
            SensorType.motion => Icons.sensors,
            SensorType.temperature => Icons.thermostat,
          },
          color: sensor.connected ? null : Theme.of(context).disabledColor,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!sensor.connected)
              const Chip(
                visualDensity: VisualDensity.compact,
                label: Text('offline'),
              ),
            if (sensor.matterForwardingPending)
              const Chip(
                visualDensity: VisualDensity.compact,
                label: Text('wird bestätigt'),
              )
            else if (sensor.displayedMatterForwarding)
              const Chip(
                visualDensity: VisualDensity.compact,
                label: Text('Matter'),
              ),
            IconButton(
              tooltip: '${sensor.name} löschen',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateSensorButton extends StatelessWidget {
  const _CreateSensorButton({required this.api});

  final SensorApi api;

  @override
  Widget build(BuildContext context) =>
      MutationBuilder<Sensor, CreateInput, void>(
        options: createSensorMutation(QueryClientProvider.of(context), api),
        builder: (context, create) => IconButton(
          tooltip: 'Sensor anlegen',
          onPressed: create.value.isPending
              ? null
              : () => create.mutate((
                    name: 'Neuer Sensor',
                    room: null,
                    type: null,
                  )),
          icon: create.value.isPending
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
        ),
      );
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) => const Center(
        key: ValueKey<String>('list-skeleton'),
        child: CircularProgressIndicator(),
      );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('$error'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Nochmal versuchen'),
            ),
          ],
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.errorContainer,
        padding: const EdgeInsets.all(12),
        child: Text(text),
      );
}
