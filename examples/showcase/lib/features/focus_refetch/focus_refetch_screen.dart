/// Focus refetch: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature focusRefetchFeature = Feature(
  id: 'focus-refetch',
  title: 'Focus refetch',
  summary: 'What happens when the app comes back to the foreground.',
);

class FocusRefetchScreen extends StatelessWidget {
  const FocusRefetchScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: focusRefetchFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
