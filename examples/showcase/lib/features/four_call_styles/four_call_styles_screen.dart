/// Four call styles: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature fourCallStylesFeature = Feature(
  id: 'four-call-styles',
  title: 'Four call styles',
  summary: 'The same query through context, builder, mixin and controller.',
);

class FourCallStylesScreen extends StatelessWidget {
  const FourCallStylesScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: fourCallStylesFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
