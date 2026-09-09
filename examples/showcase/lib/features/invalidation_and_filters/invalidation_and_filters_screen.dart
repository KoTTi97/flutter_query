/// Invalidation and filters: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature invalidationAndFiltersFeature = Feature(
  id: 'invalidation-and-filters',
  title: 'Invalidation and filters',
  summary:
      'Invalidate, refetch, reset and remove, by prefix, type or predicate.',
);

class InvalidationAndFiltersScreen extends StatelessWidget {
  const InvalidationAndFiltersScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: invalidationAndFiltersFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
