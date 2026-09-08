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
import '../queries.dart';

class SensorDetail extends StatefulWidget {
  const SensorDetail({super.key, required this.id, required this.api});

  final String id;
  final SensorApi api;

  @override
  State<SensorDetail> createState() => _SensorDetailState();
}

class _SensorDetailState extends State<SensorDetail> with QueryMixin {
  final TextEditingController _name = TextEditingController();
  String? _nameFor;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
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
        title: Text(data?.name ?? 'Sensor'),
      ),
      body: switch (sensor) {
        // In practice this is almost never seen: opening a sensor from the
        // overview renders from the entry the list already seeded. It shows up
        // when a detail screen is the first thing loaded.
        QueryPending() => const Center(child: CircularProgressIndicator()),
        QueryError(:final error, staleData: null) =>
          Center(child: Text('$error')),
        QuerySuccess(:final data) ||
        QueryError(staleData: final data!) =>
          ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (rename.value case MutationError(:final error))
                _Banner(text: '$error'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      TextField(
                        controller: _name,
                        // A failed submit's banner goes away as soon as the
                        // user edits again.
                        onChanged: (_) {
                          if (rename.value.isError) {
                            rename.reset();
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                          helperText: 'Der Name "fail" lässt das Gateway '
                              'ablehnen — für den Rollback.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: rename.value.isPending
                            ? null
                            : () => rename.mutate(
                                  (id: data.id, name: _name.text.trim()),
                                ),
                        child: Text(
                          rename.value.isPending
                              ? 'Wird gespeichert…'
                              : 'Umbenennen',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: SwitchListTile(
                  title: const Text('Matter-Weiterleitung'),
                  subtitle: Text(
                    data.matterForwardingPending
                        ? 'Wird vom Gerät bestätigt…'
                        : 'Bestätigter Gerätezustand',
                  ),
                  // `target ?? confirmed`: the requested value outranks the
                  // confirmed one while a write is outstanding, which is what
                  // stops the switch flickering during the poll.
                  value: data.displayedMatterForwarding,
                  onChanged: matter.value.isPending
                      ? null
                      : (value) => matter.mutate((id: data.id, value: value)),
                  secondary: data.matterForwardingPending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Typ: ${data.type.label}'),
                      Text('Raum: ${data.room}'),
                      Text('Batterie: ${data.battery} %'),
                      Text('Temperatur: ${data.temperature} °C'),
                      Text(data.connected ? 'Verbunden' : 'Offline'),
                    ],
                  ),
                ),
              ),
            ],
          ),
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        color: Theme.of(context).colorScheme.errorContainer,
        padding: const EdgeInsets.all(12),
        child: Text(text),
      );
}
