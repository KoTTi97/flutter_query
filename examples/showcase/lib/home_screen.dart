/// The catalogue as a list: one row per feature, tap to open.
library;

import 'package:flutter/material.dart';

import 'routes.dart';
import 'shared/scope.dart';

/// The app's name: the home screen's title, the browser tab's, and what the
/// widget tests look for to know they are back in the catalogue.
const String showcaseTitle = 'query_kit showcase';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final label = ShowcaseScope.of(context).backendLabel;
    return Scaffold(
      appBar: AppBar(
        title: const Text(showcaseTitle),
        actions: <Widget>[
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
            children: <Widget>[
              for (final entry in featureEntries)
                ListTile(
                  title: Text(entry.feature.title),
                  subtitle: Text(entry.feature.summary),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).pushNamed(entry.feature.route),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
