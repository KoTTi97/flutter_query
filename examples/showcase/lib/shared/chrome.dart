/// What a screen is made of, and what none of it means to a test.
///
/// The third of the showcase's three widget modules, and they are split by
/// what a test does with them: it **reads** a `fact_group.dart` group by name,
/// it **presses** a `controls.dart` button by name, and it does neither to
/// anything here. That is not a coincidence of what each one looks like — it
/// is what these four widgets are *for*, and each of them says so in its own
/// doc: [SectionCard] opts out of being a semantic container so the texts
/// inside it stay findable, [SkeletonBox] excludes itself from the tree
/// altogether, and [Pill] and [Notice] are leaf texts a test may match but
/// never addresses as a thing.
///
/// So the whole file is one sentence: the theme given a shape. Every class
/// here is a `StatelessWidget` that reads `Theme.of(context)`, holds no state,
/// takes no callback, and publishes no name to either test layer. A widget
/// that wants any of those four is not chrome and belongs in one of the other
/// two modules (#69).
///
/// The `ThemeData` itself is *not* here: it has exactly one caller and always
/// will, so it lives beside the `MaterialApp` it configures in `main.dart`.
library;

import 'package:flutter/material.dart';

/// A card with a heading, the unit every screen is laid out in.
///
/// Not a semantic container: a `Card` that is one folds every text inside it
/// into its own accessible name, and a browser-driving test can then find
/// the card but not the text. Left open, each text stays a node of its own.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
        semanticContainer: false,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

/// A small coloured label.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? scheme.primary).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: color ?? scheme.primary),
      ),
    );
  }
}

/// An inline notice, for errors and rollbacks.
class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: error ? scheme.onErrorContainer : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// A loading placeholder.
///
/// Deliberately not animated: a repeating animation never lets
/// `pumpAndSettle` finish, and the widget tests lean on it.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.height = 16, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
}
