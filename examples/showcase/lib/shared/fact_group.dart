/// How the showcase publishes a fact to its tests, and the one rule its two
/// test layers share.
///
/// A screen tells a test what the library did by printing `key=value` texts
/// into a **semantics group**: a container node with a name, whose children
/// stay nodes of their own. The widget tests find the group by its key and the
/// fact by its exact text; the end-to-end suite finds the same group with
/// `getByRole('group', { name })` and the same fact with `getByText`.
///
/// **One name.** Before this module every screen spelled the group twice — a
/// semantics label and a widget key — and invented the relation between them:
/// `debug x`/`debug-x`, `x facts`/`facts-x`, `facts x`/`facts-x`,
/// `x`/`x-facts`, `entry x`/`entry-x`, `post 3`/`post-row-3`. Thirty-one named
/// groups, thirteen label forms and six different label-to-key relations, of
/// which only four sites used the identity. Here the
/// name is **one string**, [SemanticsGroup.name], and the key is derived from
/// it in one place, so a test that knows the group's name knows how to find it
/// in either layer. Nothing derives a *label*: the names on screen are the
/// names the suites already read, and none of them moved (C56, #51).
///
/// The three widgets, smallest first:
///
/// * [SemanticsGroup] — the group itself. Named or not.
/// * [FactList] — the `key=value` texts, one semantics node each.
/// * [FactGroup] — the common case: a named group whose whole content is a
///   fact list. A group that also carries a heading, a control or a nested
///   reader composes the other two instead of growing a parameter here.
///
/// `QueryDebugStrip` is a [SemanticsGroup] named `debug <label>` around a
/// heading and a dense [FactList] — the one group that is about the *cache*
/// rather than about the screen, which is why it stays its own widget in
/// `debug_strip.dart` instead of being a call to [FactGroup].
library;

import 'package:flutter/material.dart';

/// The monospace style the fact texts are printed in.
///
/// A fact is read by its exact string in both test layers, so the font matters
/// only to a human; what it buys is that `status=success` and `status=error`
/// are the same width and the wrap does not jump.
const TextStyle monoStyle = TextStyle(fontFamily: 'monospace', fontSize: 13);

/// [monoStyle] a point smaller, for the screens that print a table of facts
/// rather than a handful.
const TextStyle monoStyleSmall =
    TextStyle(fontFamily: 'monospace', fontSize: 12);

/// One semantics group: its children stay nodes of their own, and a [name]
/// makes it addressable from both test layers.
///
/// Without a name it is only the grouping — several controls in a row fold
/// into the row's own node otherwise, and a browser-driving test can then find
/// the row but not the buttons inside it.
///
/// With a name, that one string is the group's whole identity:
///
/// * the semantics label, which is what `getByRole('group', { name })` reads
///   in the end-to-end suite, and
/// * `ValueKey<String>(name)`, which is what `find.byKey` reads in the widget
///   tests — see `groupNamed` and `factIn` in `test/harness.dart`.
///
/// The key sits on the group, not on the child it wraps, so every named group
/// in the app answers to the same finder no matter what is inside it.
class SemanticsGroup extends StatelessWidget {
  const SemanticsGroup({super.key, this.name, required this.child});

  /// The group's one name, or `null` for a group that only unfolds its
  /// children.
  ///
  /// Names are short and stable, and they are what the suites assert on:
  /// renaming one is a change to every spec that reads it.
  final String? name;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final name = this.name;
    return Semantics(
      key: name == null ? null : ValueKey<String>(name),
      container: true,
      explicitChildNodes: true,
      label: name,
      child: child,
    );
  }
}

/// The `key=value` texts of a group, one semantics node each.
///
/// A wrap rather than a column: a fact is a short word pair and a screen shows
/// a handful of them on one line. [dense] is [monoStyleSmall], for the groups
/// that print a table — the debug strip's nine, the cache inspector's rows.
class FactList extends StatelessWidget {
  const FactList(this.facts, {super.key, this.dense = false});

  /// Each one becomes a `Text` of its own, found by its exact string.
  final List<String> facts;

  /// Print a point smaller, and pack the rows a little tighter.
  final bool dense;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: dense ? 2 : 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          for (final fact in facts)
            Text(fact, style: dense ? monoStyleSmall : monoStyle),
        ],
      );
}

/// A named group whose whole content is a list of facts: the common case, and
/// the shape most of the feature screens want.
///
/// `FactGroup(name: 'reader alpha', facts: [...])` is
/// `SemanticsGroup(name: 'reader alpha', child: FactList([...]))`, and a group
/// that carries anything besides facts writes that pair out rather than adding
/// a parameter here.
class FactGroup extends StatelessWidget {
  const FactGroup({
    super.key,
    required this.name,
    required this.facts,
    this.dense = false,
  });

  /// The group's one name; see [SemanticsGroup.name].
  final String name;

  /// The facts, one `Text` each.
  final List<String> facts;

  /// See [FactList.dense].
  final bool dense;

  @override
  Widget build(BuildContext context) => SemanticsGroup(
        name: name,
        child: FactList(facts, dense: dense),
      );
}
