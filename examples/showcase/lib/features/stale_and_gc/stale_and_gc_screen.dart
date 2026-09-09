/// Stale time and garbage collection: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature staleAndGcFeature = Feature(
  id: 'stale-and-gc',
  title: 'Stale time and garbage collection',
  summary: 'When data goes stale, and when an unused entry is dropped.',
);

class StaleAndGcScreen extends StatelessWidget {
  const StaleAndGcScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: staleAndGcFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
