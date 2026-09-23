/// Every feature of `query_kit_flutter` as its own screen.
///
/// Run the backend first:
///
/// ```bash
/// cd examples/showcase/server && npm install && npm run dev
/// ```
///
/// ```bash
/// flutter run -d chrome                       # or macos, or an emulator
/// flutter run --dart-define=BACKEND=http://192.168.1.5:5175/api
/// ```
///
/// The catalogue is `routes.dart`; each feature lives in
/// `lib/features/<feature>/` and says at the top what it shows and how it is
/// proven.
///
/// **Without a server**, as the documentation site's live demos run it:
///
/// ```bash
/// flutter run -d chrome --dart-define=QK_BACKEND=inmemory
/// ```
///
/// The backend is then `lib/demo/in_memory_backend.dart` in the same tab, with
/// the server's seed and its 300 ms latency. Two query parameters, before the
/// `#/route`, change how the app presents itself on the web:
///
/// - `?embed=1` — one feature, alone: the route in the hash and nothing
///   beneath it, no back button, no way into the catalogue. What the site's
///   `<LiveDemo>` frame loads: `?embed=1&semantics=1#/optimistic-updates`.
/// - `?semantics=1` — the semantics tree on from the first frame, as
///   `--dart-define=E2E=true` does, so a screen reader and Playwright see the
///   screen without a special build.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'demo/demo_mode.dart';
import 'home_screen.dart';
import 'routes.dart';
import 'shared/api.dart';
import 'shared/cache_stats.dart';
import 'shared/scope.dart';

/// Built with `--dart-define=E2E=true`, the app switches its semantics tree on
/// from the start. Flutter web paints to a canvas, so that tree — rendered as
/// `flt-semantics` DOM nodes with roles and labels — is the only thing a
/// browser-driving test can see. It is what a screen reader would get.
const bool _e2e = bool.fromEnvironment('E2E');

/// The app's one theme.
///
/// Here rather than in `lib/shared/`: a `ThemeData` has exactly one caller —
/// the [MaterialApp] below — and a module in `shared/` is something more than
/// one feature calls. What *is* shared is the theme given a shape, and
/// that is `shared/chrome.dart`.
ThemeData _showcaseTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B5FFF)),
      useMaterial3: true,
      snackBarTheme:
          const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final parameters = Uri.base.queryParameters;
  if (_e2e || parameters['semantics'] == '1') {
    SemanticsBinding.instance.ensureSemantics();
  }
  final api = inMemoryBackend
      ? inMemoryApi(await loadSeed())
      : ShowcaseApi(scenario: scenarioFromEnvironment());
  runApp(ShowcaseApp(
    api: api,
    embed: parameters['embed'] == '1',
    inMemory: inMemoryBackend,
  ));
}

class ShowcaseApp extends StatefulWidget {
  const ShowcaseApp({
    super.key,
    required this.api,
    this.client,
    this.initialRoute,
    this.embed = false,
    this.inMemory = false,
  });

  final ShowcaseApi api;

  /// Injected by the widget tests, which bring their own client.
  final QueryClient? client;

  /// Where to start; the widget tests open a feature directly. On the web the
  /// URL's hash wins over this, which is how a deep link works.
  final String? initialRoute;

  /// One feature alone, framed by the documentation site: see
  /// [onGenerateEmbeddedRoute].
  final bool embed;

  /// [api] runs over the in-memory backend; the app bar says so.
  final bool inMemory;

  @override
  State<ShowcaseApp> createState() => _ShowcaseAppState();
}

class _ShowcaseAppState extends State<ShowcaseApp> {
  /// On the process-wide `NotifyManager.shared`, which is not the default —
  /// a client constructed without one gets a manager of its own — so that a
  /// `NotifyManager.shared.batch(...)` anywhere in the app holds this
  /// client's notifications too; the `four-call-styles` screen shows what
  /// that buys. The widget-test harness builds its client the same way.
  late final QueryClient _client =
      widget.client ?? QueryClient(notifyManager: NotifyManager.shared);
  late final CacheStats _stats = CacheStats(_client);

  @override
  void dispose() {
    _stats.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => QueryClientProvider(
        client: _client,
        child: ShowcaseScope(
          api: widget.api,
          stats: _stats,
          embed: widget.embed,
          inMemory: widget.inMemory,
          child: MaterialApp(
            title: showcaseTitle,
            debugShowCheckedModeBanner: false,
            theme: _showcaseTheme(),
            initialRoute: widget.initialRoute ?? '/',
            onGenerateRoute:
                widget.embed ? onGenerateEmbeddedRoute : onGenerateRoute,
            onGenerateInitialRoutes:
                widget.embed ? onGenerateEmbeddedInitialRoutes : null,
          ),
        ),
      );
}
