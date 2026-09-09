/// Cache inspector: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature cacheInspectorFeature = Feature(
  id: 'cache-inspector',
  title: 'Cache inspector',
  summary: 'Every entry and every event, live.',
);

class CacheInspectorScreen extends StatelessWidget {
  const CacheInspectorScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: cacheInspectorFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
