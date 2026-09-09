/// The demo's visual language, in one place.
///
/// Deliberately close to the React app it mirrors: a light neutral ground,
/// white cards with a hairline border, muted metadata, and one accent colour
/// used sparingly. Material 3 supplies the components; these tokens supply the
/// restraint.
library;

import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color ground = Color(0xFFF6F7F9);
  static const Color card = Colors.white;
  static const Color border = Color(0xFFE4E7EC);
  static const Color text = Color(0xFF101828);
  static const Color muted = Color(0xFF667085);
  static const Color accent = Color(0xFF0D9488);
  static const Color accentSoft = Color(0xFFECFDF5);
  static const Color warning = Color(0xFFB54708);
  static const Color warningSoft = Color(0xFFFFFAEB);
  static const Color danger = Color(0xFFB42318);
  static const Color dangerSoft = Color(0xFFFEF3F2);
  static const Color skeleton = Color(0xFFEDF0F3);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      surface: AppColors.card,
    ).copyWith(
      error: AppColors.danger,
      onSurface: AppColors.text,
    ),
    scaffoldBackgroundColor: AppColors.ground,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
      border: _inputBorder(AppColors.border),
      enabledBorder: _inputBorder(AppColors.border),
      focusedBorder: _inputBorder(AppColors.accent, width: 1.4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.muted,
        highlightColor: AppColors.ground,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
  );
}

OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: width),
    );

/// Body text one step quieter than the title above it.
const TextStyle mutedText = TextStyle(
  color: AppColors.muted,
  fontSize: 13,
  height: 1.35,
);

const TextStyle titleText = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.1,
);

/// The white surface everything sits on.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
}

/// A small tinted label — offline, Matter, "wird bestätigt".
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.color = AppColors.muted,
    this.background = AppColors.ground,
    this.dot = false,
  });

  final String label;
  final Color color;
  final Color background;

  /// A leading dot, for a state that is in motion.
  final bool dot;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (dot) ...<Widget>[
              Container(
                height: 6,
                width: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

/// An inline failure the user should see but not be blocked by — a rejected
/// rename, a refused delete.
class Notice extends StatelessWidget {
  const Notice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.dangerSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 13, color: AppColors.danger),
              ),
            ),
          ],
        ),
      );
}

/// The rounded tile a sensor's icon sits in.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.dimmed = false});

  final IconData icon;
  final bool dimmed;

  @override
  Widget build(BuildContext context) => Container(
        height: 38,
        width: 38,
        decoration: BoxDecoration(
          color: dimmed ? AppColors.ground : AppColors.accentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 19,
          color: dimmed ? AppColors.muted : AppColors.accent,
        ),
      );
}

/// A grey block standing in for text that has not arrived.
///
/// Deliberately not animated: a repeating animation never lets
/// `pumpAndSettle` finish, and the acceptance suite leans on it.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, required this.width, this.height = 12});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: AppColors.skeleton,
          borderRadius: BorderRadius.circular(6),
        ),
      );
}

/// Centres the app's content and stops it stretching on a wide window.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: child,
        ),
      );
}
