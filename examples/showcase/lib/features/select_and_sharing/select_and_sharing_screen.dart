/// Select and structural sharing: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature selectAndSharingFeature = Feature(
  id: 'select-and-sharing',
  title: 'Select and structural sharing',
  summary: 'What a reader rebuilds on, and what it does not.',
);

class SelectAndSharingScreen extends StatelessWidget {
  const SelectAndSharingScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: selectAndSharingFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
