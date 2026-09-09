/// Playground: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature playgroundFeature = Feature(
  id: 'playground',
  title: 'Playground',
  summary: 'Todos with live knobs for stale time, gc time, latency and errors.',
  upstream: 'playground',
);

class PlaygroundScreen extends StatelessWidget {
  const PlaygroundScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: playgroundFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
