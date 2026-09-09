/// Load more and infinite scroll: not built yet. The catalogue row is here so the route and the
/// home screen already know it.
library;

import 'package:flutter/material.dart';

import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';

const Feature loadMoreFeature = Feature(
  id: 'load-more',
  title: 'Load more and infinite scroll',
  summary: 'An infinite query that appends pages as you scroll.',
  upstream: 'load-more-infinite-scroll',
);

class LoadMoreScreen extends StatelessWidget {
  const LoadMoreScreen({super.key});

  @override
  Widget build(BuildContext context) => FeatureScaffold(
        feature: loadMoreFeature,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('This screen is not built yet.'),
          ),
        ],
      );
}
