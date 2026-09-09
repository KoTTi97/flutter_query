/// Infinite query with max pages: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature maxPagesFeature = Feature(
  id: 'max-pages',
  title: 'Infinite query with max pages',
  summary: 'Pages in both directions, with a window of three.',
  upstream: 'infinite-query-with-max-pages',
);

class MaxPagesScreen extends StatelessWidget {
  const MaxPagesScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: maxPagesFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
