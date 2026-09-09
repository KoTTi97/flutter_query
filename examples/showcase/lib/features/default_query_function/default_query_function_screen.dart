/// Default query function: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature defaultQueryFunctionFeature = Feature(
  id: 'default-query-function',
  title: 'Default query function',
  summary: 'A query function derived from the key, set once as a default.',
  upstream: 'default-query-function',
);

class DefaultQueryFunctionScreen extends StatelessWidget {
  const DefaultQueryFunctionScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: defaultQueryFunctionFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
