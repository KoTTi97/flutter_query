/// The showcase without a server: the app's own `ShowcaseApi` over an
/// [InMemoryBackend] in the same tab, as the documentation site's live demos
/// run it.
///
/// Chosen at compile time — `--dart-define=QK_BACKEND=inmemory` — so a normal
/// build talks to the express server and never carries this code
/// (`tool/build_demos.sh` builds the demo one).
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';

import '../shared/api.dart';
import 'in_memory_backend.dart';

/// `--dart-define=QK_BACKEND=inmemory`: the build runs against
/// [InMemoryBackend] instead of the express server.
const bool inMemoryBackend = String.fromEnvironment('QK_BACKEND') == 'inmemory';

/// The express server's default latency (`server/config.ts`,
/// `DEFAULT_LATENCY`), so a demo shows its loading states as the real one
/// does.
const Duration demoLatency = Duration(milliseconds: 300);

/// A [ShowcaseApi] over a fresh [InMemoryBackend] holding [seed].
///
/// The base URL is never resolved — the adapter answers every request before
/// dio would open a socket — and `.invalid` says so.
ShowcaseApi inMemoryApi(
  Map<String, Object?> seed, {
  Duration latency = demoLatency,
}) =>
    ShowcaseApi(
      dio: Dio(BaseOptions(baseUrl: 'http://in-memory.invalid/api'))
        ..httpClientAdapter = InMemoryBackend(seed: seed, latency: latency),
      scenario: 'in-memory',
    );

/// Where the seed sits in the app's asset bundle: `server/seed.json` itself,
/// declared as an asset in `pubspec.yaml`, so there is no copy to drift.
const String seedAsset = 'server/seed.json';

/// The seed as the demo build reads it, from [bundle] (the app's own by
/// default). `test/demo_mode_test.dart` checks that it is `server/seed.json`.
Future<Map<String, Object?>> loadSeed([AssetBundle? bundle]) async =>
    jsonDecode(await (bundle ?? rootBundle).loadString(seedAsset))
        as Map<String, Object?>;

/// The colour scheme a URL asks for: `?theme=dark` or `?theme=light`, which
/// the documentation site's `<LiveDemo>` passes so an embedded demo follows
/// the site's own light or dark mode.
///
/// Anything else — no parameter, or a value this does not know — is `null`,
/// and the app keeps its light theme.
ThemeMode? themeModeFrom(Map<String, String> parameters) =>
    switch (parameters['theme']) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => null,
    };
