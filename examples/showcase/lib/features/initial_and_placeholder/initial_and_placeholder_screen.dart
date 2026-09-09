/// Initial and placeholder data: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature initialAndPlaceholderFeature = Feature(
  id: 'initial-and-placeholder',
  title: 'Initial and placeholder data',
  summary: 'Data before the first fetch: written to the cache, or shown only.',
);

class InitialAndPlaceholderScreen extends StatelessWidget {
  const InitialAndPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: initialAndPlaceholderFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
