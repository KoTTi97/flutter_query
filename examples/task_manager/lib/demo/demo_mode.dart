/// The task manager without a server: the app's own [TaskApi] over an
/// [InMemoryBackend] in the same tab, as the documentation site embeds it.
///
/// Chosen at compile time — `--dart-define=QK_BACKEND=inmemory` — so a normal
/// build talks to the express server and never carries this code
/// (`tool/build_demos.sh` builds the demo one).
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show Brightness;

import '../src/api.dart';
import 'in_memory_backend.dart';

/// `--dart-define=QK_BACKEND=inmemory`: the build runs against
/// [InMemoryBackend] instead of the express server.
const bool inMemoryBackend = String.fromEnvironment('QK_BACKEND') == 'inmemory';

/// A [TaskApi] over a fresh [InMemoryBackend] that takes as long as the
/// express server does by default (`server/config.ts`): 900 ms for the list,
/// 350 ms for a task, 700 ms for a write, and 3 s for the reminder scheduler
/// to confirm — slow on purpose, so the loading states and the optimistic
/// writes are there to be seen.
///
/// The base URL is never resolved — the adapter answers every request before
/// dio would open a socket — and `.invalid` says so. The seed is the
/// backend's own three rows, not the server's five (see
/// [InMemoryBackend.tasks]).
TaskApi inMemoryTaskApi() => TaskApi(
      dio: Dio(BaseOptions(baseUrl: 'http://in-memory.invalid/api'))
        ..httpClientAdapter = InMemoryBackend(
          listLatency: const Duration(milliseconds: 900),
          detailLatency: const Duration(milliseconds: 350),
          writeLatency: const Duration(milliseconds: 700),
          confirmAfter: const Duration(seconds: 3),
        ),
    );

/// The brightness a URL asks for: `?theme=dark` or `?theme=light`, which the
/// documentation site's `<LiveDemo>` passes so an embedded demo follows the
/// site's own light or dark mode. Anything else is `null`: the app stays
/// light, as it always was.
Brightness? brightnessFrom(Map<String, String> parameters) =>
    switch (parameters['theme']) {
      'dark' => Brightness.dark,
      'light' => Brightness.light,
      _ => null,
    };
