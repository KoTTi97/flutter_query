/// Parallel queries: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature parallelQueriesFeature = Feature(
  id: 'parallel-queries',
  title: 'Parallel queries',
  summary: 'Several queries in one widget, and the global fetching count.',
);

class ParallelQueriesScreen extends StatelessWidget {
  const ParallelQueriesScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: parallelQueriesFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
