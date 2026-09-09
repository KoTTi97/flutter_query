/// Prefetching: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature prefetchingFeature = Feature(
  id: 'prefetching',
  title: 'Prefetching',
  summary: 'Warm the cache before the screen that needs it opens.',
  upstream: 'prefetching',
);

class PrefetchingScreen extends StatelessWidget {
  const PrefetchingScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: prefetchingFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
