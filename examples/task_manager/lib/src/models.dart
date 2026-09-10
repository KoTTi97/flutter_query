/// The client's copy of the backend's domain model.
///
/// Hand-written, with value equality and no code generation: the demo is also
/// the answer to "what does this library ask of my data types?", and the answer
/// is `==` and `hashCode`. That is what lets the cache tell a changed task
/// from an identical one and skip a rebuild
/// (https://github.com/KoTTi97/flutter_query/issues/12).
library;

import 'package:flutter/foundation.dart';

enum Priority {
  low('Low'),
  normal('Normal'),
  high('High');

  const Priority(this.label);

  final String label;

  static Priority parse(Object? value) => Priority.values.firstWhere(
        (priority) => priority.name == value,
        orElse: () => Priority.normal,
      );
}

@immutable
class Task {
  const Task({
    required this.id,
    required this.name,
    required this.priority,
    required this.project,
    required this.progress,
    required this.estimate,
    required this.synced,
    required this.reminder,
    required this.reminderTarget,
    required this.reminderPending,
  });

  factory Task.fromJson(Map<String, Object?> json) => Task(
        id: json['id']! as String,
        name: json['name']! as String,
        priority: Priority.parse(json['priority']),
        project: json['project']! as String,
        progress: (json['progress']! as num).toInt(),
        estimate: (json['estimate']! as num).toDouble(),
        synced: json['synced']! as bool,
        reminder: json['reminder']! as bool,
        reminderTarget: json['reminderTarget'] as bool?,
        reminderPending: json['reminderPending']! as bool,
      );

  final String id;
  final String name;
  final Priority priority;
  final String project;

  /// How far along the task is, 0–100.
  final int progress;

  /// Remaining work in hours.
  final double estimate;

  /// Present on the shared board. Server-owned; the client cannot set it.
  final bool synced;

  /// Confirmed by the reminder scheduler.
  final bool reminder;

  /// The value a write is trying to reach, or `null` when nothing is
  /// outstanding.
  ///
  /// This exists so an in-flight write has somewhere to live that a poll
  /// response cannot overwrite. Without it the confirmed field is the only
  /// place to put the optimistic value, and every poll during the confirmation
  /// window stomps it back — the switch visibly flickers.
  final bool? reminderTarget;

  /// The server accepted a write the scheduler has not confirmed yet.
  final bool reminderPending;

  /// What the reminder switch should render: a requested value outranks the
  /// confirmed one for as long as the write is outstanding.
  bool get displayedReminder => reminderTarget ?? reminder;

  Task copyWith({
    String? name,
    bool? reminder,
    bool? reminderPending,
    bool? reminderTarget,
    bool clearReminderTarget = false,
  }) =>
      Task(
        id: id,
        name: name ?? this.name,
        priority: priority,
        project: project,
        progress: progress,
        estimate: estimate,
        synced: synced,
        reminder: reminder ?? this.reminder,
        reminderTarget: clearReminderTarget
            ? null
            : (reminderTarget ?? this.reminderTarget),
        reminderPending: reminderPending ?? this.reminderPending,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task &&
          other.id == id &&
          other.name == name &&
          other.priority == priority &&
          other.project == project &&
          other.progress == progress &&
          other.estimate == estimate &&
          other.synced == synced &&
          other.reminder == reminder &&
          other.reminderTarget == reminderTarget &&
          other.reminderPending == reminderPending;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        priority,
        project,
        progress,
        estimate,
        synced,
        reminder,
        reminderTarget,
        reminderPending,
      );
}

@immutable
class TaskListResponse {
  const TaskListResponse({required this.tasks, required this.fetchedAt});

  factory TaskListResponse.fromJson(Map<String, Object?> json) =>
      TaskListResponse(
        tasks: (json['tasks']! as List<Object?>)
            .map((task) => Task.fromJson(task! as Map<String, Object?>))
            .toList(),
        fetchedAt: DateTime.parse(json['fetchedAt']! as String),
      );

  final List<Task> tasks;
  final DateTime fetchedAt;

  TaskListResponse withTasks(List<Task> tasks) =>
      TaskListResponse(tasks: tasks, fetchedAt: fetchedAt);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskListResponse &&
          other.fetchedAt == fetchedAt &&
          listEquals(other.tasks, tasks);

  @override
  int get hashCode => Object.hash(fetchedAt, Object.hashAll(tasks));
}

/// What the overview is filtered by. Part of the list's query key, so it needs
/// value equality like everything else in a key.
@immutable
class TaskFilters {
  const TaskFilters({this.search = '', this.project = 'all'});

  final String search;
  final String project;

  /// The unfiltered list. Anything asking for "all tasks" must use this exact
  /// value so it lands on the same key and shares the one cache entry.
  static const TaskFilters all = TaskFilters();

  Map<String, Object?> toJson() => <String, Object?>{
        'search': search,
        'project': project,
      };

  TaskFilters copyWith({String? search, String? project}) => TaskFilters(
      search: search ?? this.search, project: project ?? this.project);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskFilters &&
          other.search == search &&
          other.project == project;

  @override
  int get hashCode => Object.hash(search, project);
}
