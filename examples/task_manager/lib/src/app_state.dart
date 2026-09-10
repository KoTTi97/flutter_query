/// Client state only.
///
/// The split that matters: anything the backend owns (tasks, their names,
/// their reminders) lives in the query cache and is never copied in here.
/// This holds the things that have no server representation at all — which
/// screen is open, what is typed into the search box.
///
/// A store that mirrored the task list would need its own fetching, staleness
/// and invalidation rules, which is exactly the hand-rolled machinery this demo
/// exists to argue against.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'models.dart';

class AppState extends ChangeNotifier {
  String? _openTaskId;
  String _search = '';
  String _debouncedSearch = '';
  String _project = 'all';
  Timer? _debounce;

  String? get openTaskId => _openTaskId;
  String get search => _search;
  String get project => _project;

  /// The typed value drives the input; this settled one drives the query key.
  /// One request per pause in typing instead of one per keystroke.
  TaskFilters get filters =>
      TaskFilters(search: _debouncedSearch, project: _project);

  void openTask(String id) {
    _openTaskId = id;
    notifyListeners();
  }

  void closeTask() {
    _openTaskId = null;
    notifyListeners();
  }

  void setSearch(String search) {
    _search = search;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _debouncedSearch = search;
      notifyListeners();
    });
  }

  void setProject(String project) {
    _project = project;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

/// Puts [AppState] in the tree and rebuilds dependents when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget.');
    return scope!.notifier!;
  }
}
