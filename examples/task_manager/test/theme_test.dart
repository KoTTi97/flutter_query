/// `?theme=dark`, as the documentation site's `<LiveDemo>` passes it when the
/// site is dark: the parameter, and the palette it selects.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/demo/demo_mode.dart';
import 'package:task_manager/src/theme.dart';

void main() {
  test('?theme= names a brightness, and nothing else does', () {
    expect(brightnessFrom(const <String, String>{'theme': 'dark'}),
        Brightness.dark);
    expect(brightnessFrom(const <String, String>{'theme': 'light'}),
        Brightness.light);
    expect(brightnessFrom(const <String, String>{}), isNull);
    expect(brightnessFrom(const <String, String>{'theme': 'dim'}), isNull);
  });

  test('the app is light unless the dark palette is chosen', () {
    expect(AppColors.palette, same(AppPalette.light));
    expect(buildAppTheme().brightness, Brightness.light);
    addTearDown(() => AppColors.palette = AppPalette.light);

    AppColors.palette = AppPalette.dark;
    final ThemeData dark = buildAppTheme();
    expect(dark.brightness, Brightness.dark);
    expect(dark.scaffoldBackgroundColor, AppPalette.dark.ground);
  });
}
