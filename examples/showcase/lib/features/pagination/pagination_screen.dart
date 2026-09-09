/// Pagination: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature paginationFeature = Feature(
  id: 'pagination',
  title: 'Pagination',
  summary:
      'Page by page, keeping the previous page on screen while the next loads.',
  upstream: 'pagination',
);

class PaginationScreen extends StatelessWidget {
  const PaginationScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: paginationFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
