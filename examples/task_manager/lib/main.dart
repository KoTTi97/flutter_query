/// A task manager on `query_kit_flutter`, against the express backend in
/// `server/`.
///
/// Run the backend first:
///
/// ```bash
/// cd examples/task_manager/server && npm install && npm run dev
/// ```
///
/// ```bash
/// flutter run -d chrome                       # or macos, or an emulator
/// flutter run --dart-define=BACKEND=http://192.168.1.5:5174/api
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'src/api.dart';
import 'src/app_state.dart';
import 'src/queries.dart';
import 'src/screens/detail.dart';
import 'src/screens/overview.dart';
import 'src/theme.dart';
import 'src/widgets/header.dart';

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
  runApp(TaskManagerApp(api: TaskApi()));
}

class TaskManagerApp extends StatefulWidget {
  const TaskManagerApp({super.key, required this.api, this.client});

  final TaskApi api;

  /// Injected by the widget tests, which bring their own client.
  final QueryClient? client;

  @override
  State<TaskManagerApp> createState() => _TaskManagerAppState();
}

class _TaskManagerAppState extends State<TaskManagerApp> {
  late final QueryClient _client =
      widget.client ?? QueryClient(defaultOptions: appDefaultOptions);
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
            title: 'Task Manager',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: _Home(api: widget.api),
          ),
        ),
      );
}

class _Home extends StatelessWidget {
  const _Home({required this.api});

  final TaskApi api;

  @override
  Widget build(BuildContext context) {
    // Which screen is open is client state, so it lives in AppState — not in
    // the query cache.
    final openTaskId = AppScope.of(context).openTaskId;
    if (openTaskId != null) {
      return TaskDetail(id: openTaskId, api: api);
    }
    return Scaffold(
      appBar: AppHeader(api: api),
      body: TaskOverview(api: api),
    );
  }
}
