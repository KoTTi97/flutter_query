/// Basic: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature basicFeature = Feature(
  id: 'basic',
  title: 'Basic',
  summary: 'A list, a detail, and what the cache already knows.',
  upstream: 'basic',
);

class BasicScreen extends StatelessWidget {
  const BasicScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: basicFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
