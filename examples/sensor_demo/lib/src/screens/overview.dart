/// The overview: search, room filter, refresh, create, delete — and the rows.
///
/// Two of the binding's four styles earn their place here:
///
/// * the screen holds a **`QueryController`** for the list, because the toolbar
///   and the body are siblings that both need it (refresh disabled while
///   fetching, error panel, the rows). One controller and two small
///   `ListenableBuilder`s beat one builder wrapping the whole screen.
/// * each row uses **`context.query`**, because rows read *different* keys and
///   that style rebuilds only the row whose sensor changed.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../api.dart';
import '../app_state.dart';
import '../models.dart';
import '../queries.dart';
import '../theme.dart';

/// The rooms the gateway actually uses.
const List<String> rooms = <String>[
  'all',
  'Küche',
  'Flur',
  'Wohnzimmer',
  'Schlafzimmer',
  'Garage',
];

IconData iconFor(SensorType type) => switch (type) {
      SensorType.contact => Icons.sensor_door_outlined,
      SensorType.motion => Icons.sensors,
      SensorType.temperature => Icons.thermostat,
    };

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

    return ContentWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Text(
              'Sensoren',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Text(
              'Sensoren am Gateway. Das Gateway ist absichtlich langsam — '
              'rund 900 ms pro Listenabruf — damit man den Cache arbeiten sieht.',
              style: mutedText,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: app.setSearch,
                    decoration: const InputDecoration(
                      hintText: 'Sensoren durchsuchen…',
                      prefixIcon: Icon(Icons.search, size: 18),
                      prefixIconConstraints:
                          BoxConstraints(minWidth: 40, minHeight: 36),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _RoomFilter(value: app.room, onChanged: app.setRoom),
                const SizedBox(width: 6),
                // The refresh button needs `isFetching` from the same query the
                // body renders — the reason the controller sits on the State.
                ListenableBuilder(
                  listenable: _list!,
                  builder: (context, _) {
                    final fetching = _list!.value.isFetching;
                    return IconButton(
                      tooltip: 'Neu laden',
                      onPressed: fetching ? null : () => _list!.refetch(),
                      icon: fetching
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.muted,
                              ),
                            )
                          : const Icon(Icons.refresh, size: 20),
                    );
                  },
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
      ),
    );
  }
}

class _RoomFilter extends StatelessWidget {
  const _RoomFilter({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            borderRadius: BorderRadius.circular(10),
            icon: const Icon(Icons.expand_more, size: 18),
            style: const TextStyle(fontSize: 14, color: AppColors.text),
            onChanged: (room) => onChanged(room ?? 'all'),
            items: <DropdownMenuItem<String>>[
              for (final room in rooms)
                DropdownMenuItem<String>(
                  value: room,
                  child: Text(room == 'all' ? 'Alle Räume' : room),
                ),
            ],
          ),
        ),
      );
}

class _SensorList extends StatelessWidget {
  const _SensorList({required this.sensors, required this.api});

  final List<Sensor> sensors;
  final SensorApi api;

  @override
  Widget build(BuildContext context) =>
      MutationBuilder<String, String, ListSnapshot>(
        options: deleteSensorMutation(QueryClientProvider.of(context), api),
        // The builder sits above the empty state on purpose: deleting the
        // last visible sensor empties the list optimistically, and if the
        // empty state replaced the builder, the rollback would still run but
        // its failure notice would be lost with the unmounted mutation.
        builder: (context, delete) => Column(
          children: <Widget>[
            if (delete.value case MutationError(:final error))
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Notice(text: '$error'),
              ),
            Expanded(
              child: sensors.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      itemCount: sensors.length,
                      separatorBuilder: (context, _) =>
                          const SizedBox(height: 8),
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

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      onTap: () => AppScope.of(context).openSensor(id),
      child: Row(
        children: <Widget>[
          IconTile(icon: iconFor(sensor.type), dimmed: !sensor.connected),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  sensor.name,
                  style: titleText.copyWith(
                    color: sensor.connected ? AppColors.text : AppColors.muted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                _MetaLine(sensor: sensor),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (sensor.matterForwardingPending)
            const StatusPill(
              label: 'wird bestätigt',
              color: AppColors.warning,
              background: AppColors.warningSoft,
              dot: true,
            )
          else if (!sensor.connected)
            const StatusPill(label: 'offline')
          else if (sensor.displayedMatterForwarding)
            const StatusPill(
              label: 'Matter',
              color: AppColors.accent,
              background: AppColors.accentSoft,
            ),
          IconButton(
            tooltip: '${sensor.name} löschen',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 19),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.sensor});

  final Sensor sensor;

  @override
  Widget build(BuildContext context) {
    final low = sensor.battery < 20;
    return DefaultTextStyle(
      style: mutedText.copyWith(fontSize: 12.5),
      child: Row(
        children: <Widget>[
          Text(sensor.type.label),
          const _Dot(),
          Text(sensor.room),
          const _Dot(),
          Text(
            '${sensor.battery} %',
            style: mutedText.copyWith(
              fontSize: 12.5,
              color: low ? AppColors.danger : AppColors.muted,
              fontWeight: low ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text('·'),
      );
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
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.muted,
                  ),
                )
              : const Icon(Icons.add, size: 20),
        ),
      );
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) => ListView.separated(
        key: const ValueKey<String>('list-skeleton'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        itemCount: 4,
        separatorBuilder: (context, _) => const SizedBox(height: 8),
        itemBuilder: (context, _) => SurfaceCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: <Widget>[
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: AppColors.skeleton,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SkeletonBox(width: 150, height: 13),
                  SizedBox(height: 8),
                  SkeletonBox(width: 210, height: 11),
                ],
              ),
            ],
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.sensors_off, size: 30, color: AppColors.muted),
            SizedBox(height: 10),
            Text('Keine Sensoren gefunden.', style: mutedText),
          ],
        ),
      );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SurfaceCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.cloud_off, size: 26, color: AppColors.danger),
                const SizedBox(height: 12),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: titleText,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Läuft das Gateway auf Port 5174?',
                  style: mutedText,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Nochmal versuchen'),
                ),
              ],
            ),
          ),
        ),
      );
}
