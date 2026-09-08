/// The header badge: "x von y verbunden".
///
/// Reads the *same* cache entry as the overview's unfiltered list, through
/// `select`. Two widgets, two shapes of one fetch — and this one is a leaf, so
/// a builder is the honest fit (of the four styles the binding offers, it is
/// the one that stays visible in the tree).
library;

import 'package:flutter/material.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

import '../api.dart';
import '../models.dart';
import '../queries.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({super.key, required this.api});

  final SensorApi api;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    return AppBar(
      title: const Text('Sensor-Gateway'),
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: QuerySelectBuilder<SensorListResponse,
                ({int connected, int total})>(
              options: connectedSensorsQuery(client, api),
              builder: (context, result) => switch (result) {
                QuerySuccess(:final data) => Chip(
                    visualDensity: VisualDensity.compact,
                    label:
                        Text('${data.connected} von ${data.total} verbunden'),
                  ),
                QueryError() => const Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Gateway offline'),
                  ),
                QueryPending() => const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              },
            ),
          ),
        ),
      ],
    );
  }
}
