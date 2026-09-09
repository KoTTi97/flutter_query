/// Auto refetching: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature autoRefetchingFeature = Feature(
  id: 'auto-refetching',
  title: 'Auto refetching',
  summary: 'Polling on an interval, in the foreground or not.',
  upstream: 'auto-refetching',
);

class AutoRefetchingScreen extends StatelessWidget {
  const AutoRefetchingScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: autoRefetchingFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
