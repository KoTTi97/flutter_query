/// The react-demo sensor manager, on `tanstack_query_flutter`.
///
/// Run the gateway first:
///
/// ```bash
/// cd react-demo/server && npm install && npm run dev
/// ```
///
/// ```bash
/// flutter run -d chrome                       # or macos, or an emulator
/// flutter run --dart-define=GATEWAY=http://192.168.1.5:5174/api
/// ```
library;

import 'package:flutter/material.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

import 'src/api.dart';
import 'src/app_state.dart';
import 'src/queries.dart';
import 'src/screens/detail.dart';
import 'src/screens/overview.dart';
import 'src/theme.dart';
import 'src/widgets/header.dart';

void main() => runApp(SensorDemoApp(api: SensorApi()));

class SensorDemoApp extends StatefulWidget {
  const SensorDemoApp({super.key, required this.api, this.client});

  final SensorApi api;

  /// Injected by the widget tests, which bring their own client.
  final QueryClient? client;

  @override
  State<SensorDemoApp> createState() => _SensorDemoAppState();
}

class _SensorDemoAppState extends State<SensorDemoApp> {
  late final QueryClient _client =
      widget.client ?? QueryClient(defaultOptions: demoDefaultOptions);
  final AppState _state = AppState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => QueryClientProvider(
        client: _client,
        child: AppScope(
          state: _state,
          child: MaterialApp(
            title: 'Sensor-Gateway',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: _Home(api: widget.api),
          ),
        ),
      );
}

class _Home extends StatelessWidget {
  const _Home({required this.api});

  final SensorApi api;

  @override
  Widget build(BuildContext context) {
    // Which screen is open is client state, so it lives in AppState — not in
    // the query cache.
    final openSensorId = AppScope.of(context).openSensorId;
    if (openSensorId != null) {
      return SensorDetail(id: openSensorId, api: api);
    }
    return Scaffold(
      appBar: AppHeader(api: api),
      body: SensorOverview(api: api),
    );
  }
}
