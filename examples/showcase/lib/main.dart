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
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'routes.dart';
import 'shared/api.dart';
import 'shared/cache_stats.dart';
import 'shared/scope.dart';
import 'shared/theme.dart';

/// Built with `--dart-define=E2E=true`, the app switches its semantics tree on
/// from the start. Flutter web paints to a canvas, so that tree — rendered as
/// `flt-semantics` DOM nodes with roles and labels — is the only thing a
/// browser-driving test can see. It is what a screen reader would get.
const bool _e2e = bool.fromEnvironment('E2E');

void main() {
  if (_e2e) {
    WidgetsFlutterBinding.ensureInitialized();
    SemanticsBinding.instance.ensureSemantics();
  }
  runApp(ShowcaseApp(api: ShowcaseApi(scenario: scenarioFromEnvironment())));
}

class ShowcaseApp extends StatefulWidget {
  const ShowcaseApp({
    super.key,
    required this.api,
    this.client,
    this.initialRoute,
  });

  final ShowcaseApi api;

  /// Injected by the widget tests, which bring their own client.
  final QueryClient? client;

  /// Where to start; the widget tests open a feature directly. On the web the
  /// URL's hash wins over this, which is how a deep link works.
  final String? initialRoute;

  @override
  State<ShowcaseApp> createState() => _ShowcaseAppState();
}

class _ShowcaseAppState extends State<ShowcaseApp> {
  late final QueryClient _client = widget.client ?? QueryClient();
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
          child: MaterialApp(
            title: 'TanStack Query Showcase',
            debugShowCheckedModeBanner: false,
            theme: buildShowcaseTheme(),
            initialRoute: widget.initialRoute ?? '/',
            onGenerateRoute: onGenerateRoute,
          ),
        ),
      );
}
