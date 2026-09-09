/// Cancellation: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature cancellationFeature = Feature(
  id: 'cancellation',
  title: 'Cancellation',
  summary: 'A query cancelled is a request aborted.',
);

class CancellationScreen extends StatelessWidget {
  const CancellationScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: cancellationFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
