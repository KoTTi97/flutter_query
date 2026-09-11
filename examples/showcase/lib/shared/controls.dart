/// The controls more than one feature screen drives itself with, and the two
/// formats they print in.
///
/// Every one of these was copied between feature directories until the
/// review's C55 counted the copies: the toolbar four times, the action button
/// six, the knob four, the monospace style five, the clock five. What differed
/// between copies is a parameter here; what differed in kind — the knob that
/// is one cell of a `Wrap` rather than a row of a stretched `Column` — is
/// composed from [knobButton] instead of flagged.
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

/// A local wall clock as `hh:mm:ss`.
///
/// Never a date and never a duration: a test asserts that two readings differ,
/// not what either one is — nothing in the suites asserts on a clock.
String hhmmss(DateTime at) {
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

/// A row of buttons in one semantics group.
///
/// Several controls in a row otherwise fold into the row's own node and a
/// browser-driving test can find the row but not the buttons.
class Toolbar extends StatelessWidget {
  const Toolbar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        explicitChildNodes: true,
        child: Wrap(spacing: 8, runSpacing: 8, children: children),
      );
}

/// A button named by its label; the tooltip stays out of the semantics tree.
///
/// `IconButton(tooltip:)` is named by its tooltip, but a [Tooltip] wrapped
/// around a text button is not — there the visible label is the accessible
/// name, and `excludeFromSemantics` keeps the hover text from doubling it.
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.dense = false,
  });

  /// The visible text, the tooltip, and the accessible name: one string.
  final String label;

  /// `null` disables the button, which is a fact some screens show on purpose.
  final VoidCallback? onPressed;

  /// A tonal filled button rather than an outlined one — the emphasis a screen
  /// gives its primary action.
  final bool filled;

  /// Compact density and a shrink-wrapped tap target, for the screens that put
  /// a button on every row of a list.
  final bool dense;

  static const ButtonStyle _dense = ButtonStyle(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    final style = dense ? _dense : null;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: filled
          ? FilledButton.tonal(
              onPressed: onPressed,
              style: style,
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: style,
              child: Text(label),
            ),
    );
  }
}

/// The knob itself: a compact [SegmentedButton] in a named semantics group, so
/// a test can pick this knob's `2` apart from another knob's.
///
/// A function rather than a widget class, so that what a screen builds is
/// exactly what it built when each screen carried its own copy.
Widget knobButton<T extends Object>({
  required String semanticsKey,
  required List<(String, T)> choices,
  required T selected,
  required ValueChanged<T> onChanged,
}) =>
    Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticsKey,
      child: SegmentedButton<T>(
        key: ValueKey<String>(semanticsKey),
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: <ButtonSegment<T>>[
          for (final (label, value) in choices)
            ButtonSegment<T>(value: value, label: Text(label)),
        ],
        selected: <T>{selected},
        onSelectionChanged: (selection) => onChanged(selection.single),
      ),
    );

/// One knob, stacked: its name above [knobButton].
///
/// The shape for a knob that is a row of a stretched `Column` — it takes the
/// full width and scrolls sideways rather than overflowing on a narrow phone.
/// A knob that is one cell of a `Wrap` must shrink-wrap instead and cannot
/// carry an unbounded scroller, so that screen composes [knobButton] itself.
Widget knob<T extends Object>(
  BuildContext context, {
  required String name,
  required String semanticsKey,
  required List<(String, T)> choices,
  required T selected,
  required ValueChanged<T> onChanged,
}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(name, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        // Scrolls sideways rather than overflowing on a narrow phone.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: knobButton<T>(
            semanticsKey: semanticsKey,
            choices: choices,
            selected: selected,
            onChanged: onChanged,
          ),
        ),
      ],
    );
