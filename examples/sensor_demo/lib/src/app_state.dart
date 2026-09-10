/// Client state only.
///
/// The split that matters: anything the gateway owns (sensors, their names,
/// their Matter state) lives in the query cache and is never copied in here.
/// This holds the things that have no server representation at all — which
/// screen is open, what is typed into the search box.
///
/// A store that mirrored the sensor list would need its own fetching, staleness
/// and invalidation rules, which is exactly the hand-rolled machinery this demo
/// exists to argue against.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'models.dart';

class AppState extends ChangeNotifier {
  String? _openSensorId;
  String _search = '';
  String _debouncedSearch = '';
  String _room = 'all';
  Timer? _debounce;

  String? get openSensorId => _openSensorId;
  String get search => _search;
  String get room => _room;

  /// The typed value drives the input; this settled one drives the query key.
  /// One request per pause in typing instead of one per keystroke.
  SensorFilters get filters =>
      SensorFilters(search: _debouncedSearch, room: _room);

  void openSensor(String id) {
    _openSensorId = id;
    notifyListeners();
  }

  void closeSensor() {
    _openSensorId = null;
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

  void setRoom(String room) {
    _room = room;
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
