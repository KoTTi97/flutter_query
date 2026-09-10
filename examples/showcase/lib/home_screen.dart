/// The catalogue as a list: one row per feature, tap to open.
library;

import 'package:flutter/material.dart';

import 'routes.dart';
import 'shared/scope.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scenario = ShowcaseScope.apiOf(context).scenario;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TanStack Query Showcase'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                'scenario $scenario',
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
