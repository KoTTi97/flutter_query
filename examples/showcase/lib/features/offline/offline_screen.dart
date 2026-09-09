/// Offline: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature offlineFeature = Feature(
  id: 'offline',
  title: 'Offline',
  summary: 'Network modes, paused mutations, and coming back online.',
  upstream: 'offline',
);

class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: offlineFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
