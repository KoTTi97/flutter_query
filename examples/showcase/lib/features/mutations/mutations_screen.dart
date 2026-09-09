/// Mutations: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature mutationsFeature = Feature(
  id: 'mutations',
  title: 'Mutations',
  summary: 'mutate, mutateAsync, reset, callbacks, and scopes.',
);

class MutationsScreen extends StatelessWidget {
  const MutationsScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: mutationsFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
