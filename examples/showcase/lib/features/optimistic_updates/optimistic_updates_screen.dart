/// Optimistic updates: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature optimisticUpdatesFeature = Feature(
  id: 'optimistic-updates',
  title: 'Optimistic updates',
  summary: 'Show the write before the server answers — two ways.',
  upstream: 'nextjs-app-optimistic-updates',
);

class OptimisticUpdatesScreen extends StatelessWidget {
  const OptimisticUpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: optimisticUpdatesFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
