/// The detail screen: rename with rollback, and the Matter switch whose write
/// is confirmed by the device seconds later.
///
/// Uses the binding's **`QueryMixin`**, because this screen is stateful anyway
/// (the rename field needs a `TextEditingController`) and the mixin puts the
/// query and both mutations flat at the top of `build`, with the `State` owning
/// their lifetime.
library;

import 'package:flutter/material.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

import '../api.dart';
import '../app_state.dart';
import '../models.dart';
import '../queries.dart';
import '../theme.dart';
import 'overview.dart' show iconFor;

class SensorDetail extends StatefulWidget {
  const SensorDetail({super.key, required this.id, required this.api});

  final String id;
  final SensorApi api;

  @override
  State<SensorDetail> createState() => _SensorDetailState();
}

class _SensorDetailState extends State<SensorDetail> with QueryMixin {
  final TextEditingController _name = TextEditingController();

  /// Which sensor the field was filled for.
  String? _nameFor;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _syncName(QueryClient client, String id) {
    if (!mounted) return;
    final name = client.getQueryData<Sensor>(SensorKeys.detail(id))?.name;
    if (name != null) _name.text = name;
  }

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);

    final sensor = watchQuery(sensorQuery(client, widget.api, widget.id));
    final rename = watchMutation(renameSensorMutation(client, widget.api));
    final matter =
        watchMutation(setMatterForwardingMutation(client, widget.api));

    final data = sensor.dataOrNull;
    if (data != null && _nameFor != data.id) {
      _name.text = data.name;
      _nameFor = data.id;
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: AppScope.of(context).closeSensor),
        title: const Text('Alle Sensoren'),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
        child: switch (sensor) {
          // In practice this is almost never seen: opening a sensor from the
          // overview renders from the entry the list already seeded. It shows
          // up when a detail screen is the first thing loaded.
          QueryPending() => const _DetailSkeleton(),
          QueryError(:final error, staleData: null) => _DetailError('$error'),
          QuerySuccess(:final data) ||
          QueryError(staleData: final data!) =>
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              children: <Widget>[
                _Hero(sensor: data),
                const SizedBox(height: 14),
                if (rename.value case MutationError(:final error)) ...<Widget>[
                  Notice(text: '$error'),
                  const SizedBox(height: 14),
                ],
                _RenameCard(
                  controller: _name,
                  pending: rename.value.isPending,
                  // A failed submit's banner goes away as soon as the user
                  // edits again.
                  onChanged: rename.value.isError ? rename.reset : null,
                  onSubmit: () => rename.mutate(
                    (id: data.id, name: _name.text.trim()),
                    // Once the rename has settled, the field shows what the
                    // cache holds: the submitted name after a success, the old
                    // one after a rollback. React gets the same from `reset`
                    // in `onSuccess` plus the form's `values` re-sync.
                    callbacks:
                        MutateCallbacks<Sensor, RenameInput, SensorSnapshot>(
                      onSettled: (_, __, ___, ____, _____) =>
                          _syncName(client, data.id),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _MatterCard(
                  sensor: data,
                  // Locked for the whole confirmation window, not only while
                  // the write is in flight — a second flip before the device
                  // has confirmed the first would race the poll.
                  pending:
                      data.matterForwardingPending || matter.value.isPending,
                  onChanged: (value) =>
                      matter.mutate((id: data.id, value: value)),
                ),
                const SizedBox(height: 14),
                _FactsCard(sensor: data),
              ],
            ),
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.sensor});

  final Sensor sensor;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: <Widget>[
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color:
                    sensor.connected ? AppColors.accentSoft : AppColors.ground,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                iconFor(sensor.type),
                size: 26,
                color: sensor.connected ? AppColors.accent : AppColors.muted,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    sensor.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('${sensor.type.label} · ${sensor.room}',
                      style: mutedText),
                ],
              ),
            ),
            if (sensor.matterForwardingPending)
              const StatusPill(
                label: 'wird bestätigt',
                color: AppColors.warning,
                background: AppColors.warningSoft,
                dot: true,
              )
            else if (!sensor.connected)
              const StatusPill(label: 'offline'),
          ],
        ),
      );
}

class _RenameCard extends StatelessWidget {
  const _RenameCard({
    required this.controller,
    required this.pending,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool pending;
  final VoidCallback? onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Name', style: titleText),
            const SizedBox(height: 3),
            const Text(
              'Wird sofort angezeigt und zurückgerollt, wenn das Gateway '
              'ablehnt. Der Name "fail" wird immer abgelehnt.',
              style: mutedText,
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged == null ? null : (_) => onChanged!(),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: pending ? null : onSubmit,
                  child: pending
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Umbenennen'),
                ),
              ],
            ),
          ],
        ),
      );
}

class _MatterCard extends StatelessWidget {
  const _MatterCard({
    required this.sensor,
    required this.pending,
    required this.onChanged,
  });

  final Sensor sensor;
  final bool pending;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Matter-Weiterleitung', style: titleText),
                  const SizedBox(height: 3),
                  Text(
                    sensor.matterForwardingPending
                        ? 'Wird vom Gerät bestätigt…'
                        : 'Bestätigter Gerätezustand',
                    style: mutedText.copyWith(
                      color: sensor.matterForwardingPending
                          ? AppColors.warning
                          : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (sensor.matterForwardingPending)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  height: 15,
                  width: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.warning,
                  ),
                ),
              ),
            Switch(
              // `target ?? confirmed`: the requested value outranks the
              // confirmed one while a write is outstanding, which is what stops
              // the switch flickering during the poll.
              value: sensor.displayedMatterForwarding,
              activeTrackColor: AppColors.accent,
              onChanged: pending ? null : onChanged,
            ),
          ],
        ),
      );
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.sensor});

  final Sensor sensor;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Column(
          children: <Widget>[
            _Fact(
              label: 'Batterie',
              value: '${sensor.battery} %',
              danger: sensor.battery < 20,
            ),
            const Divider(),
            _Fact(
              label: 'Temperatur',
              value: '${sensor.temperature.toStringAsFixed(1)} °C',
            ),
            const Divider(),
            _Fact(label: 'Raum', value: sensor.room),
            const Divider(),
            _Fact(
              label: 'Funk',
              value: sensor.connected ? 'Verbunden' : 'Offline',
            ),
          ],
        ),
      );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.danger = false});

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label, style: mutedText.copyWith(fontSize: 14)),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: danger ? AppColors.danger : AppColors.text,
              ),
            ),
          ],
        ),
      );
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: <Widget>[
          SurfaceCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: <Widget>[
                Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: AppColors.skeleton,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SkeletonBox(width: 170, height: 16),
                    SizedBox(height: 9),
                    SkeletonBox(width: 120, height: 12),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SurfaceCard(
            padding: EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonBox(width: 90, height: 13),
                SizedBox(height: 12),
                SkeletonBox(width: double.infinity, height: 40),
              ],
            ),
          ),
        ],
      );
}

class _DetailError extends StatelessWidget {
  const _DetailError(this.message);

  final String message;

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
                Text(message, textAlign: TextAlign.center, style: titleText),
              ],
            ),
          ),
        ),
      );
}
