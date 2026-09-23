/// The frame around every feature screen: title, back button, the scenario
/// this run lives in, and the catalogue's row as an intro.
///
/// Embedded in the documentation site (`?embed=1`) there is no back button —
/// the frame holds one feature and nothing to go back to — and the scenario
/// gives way to what [ShowcaseScope.backendLabel] says instead.
library;

import 'package:flutter/material.dart';

import 'feature.dart';
import 'scope.dart';

class FeatureScaffold extends StatelessWidget {
  const FeatureScaffold({
    super.key,
    required this.feature,
    required this.children,
    this.actions = const <Widget>[],
  });

  final Feature feature;

  /// The screen's sections, laid out in a scrolling column.
  final List<Widget> children;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scope = ShowcaseScope.of(context);
    final label = scope.backendLabel;
    return Scaffold(
      appBar: AppBar(
        title: Text(feature.title),
        automaticallyImplyLeading: !scope.embed,
        actions: <Widget>[
          ...actions,
          if (label != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(feature.summary),
                    if (feature.upstream != null)
                      Text(
                        'Mirrors upstream example: ${feature.upstream}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
