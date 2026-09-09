/// The wire types, typed by hand — the client's copy of the route table in
/// `server/server.ts`.
///
/// Every type carries value equality. The library asks data types for `==`
/// explicitly (https://github.com/KoTTi97/flutter_query/issues/12): a refetch
/// that returns equal data must not look like a change to a reader.
library;

import 'package:flutter/foundation.dart';

/// A post, the read-only content behind the reading screens.
class Post {
  const Post({required this.id, required this.title, required this.body});

  factory Post.fromJson(Map<String, Object?> json) => Post(
        id: json['id']! as int,
        title: json['title']! as String,
        body: json['body']! as String,
      );

  final int id;
  final String title;
  final String body;

  Map<String, Object?> toJson() =>
      <String, Object?>{'id': id, 'title': title, 'body': body};

  @override
  bool operator ==(Object other) =>
      other is Post &&
      other.id == id &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, title, body);

  @override
  String toString() => 'Post($id, $title)';
}

/// A comment on a post.
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.author,
    required this.text,
  });

  factory Comment.fromJson(Map<String, Object?> json) => Comment(
        id: json['id']! as int,
        postId: json['postId']! as int,
        author: json['author']! as String,
        text: json['text']! as String,
      );

  final int id;
  final int postId;
  final String author;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is Comment &&
      other.id == id &&
      other.postId == postId &&
      other.author == author &&
      other.text == text;

  @override
  int get hashCode => Object.hash(id, postId, author, text);

  @override
  String toString() => 'Comment($id on $postId)';
}

/// A todo, the writable resource behind the mutation screens.
class Todo {
  const Todo({required this.id, required this.text, required this.done});

  factory Todo.fromJson(Map<String, Object?> json) => Todo(
        id: json['id']! as int,
        text: json['text']! as String,
        done: json['done']! as bool,
      );

  final int id;
  final String text;
  final bool done;

  Todo copyWith({String? text, bool? done}) =>
      Todo(id: id, text: text ?? this.text, done: done ?? this.done);

  Map<String, Object?> toJson() =>
      <String, Object?>{'id': id, 'text': text, 'done': done};

  @override
  bool operator ==(Object other) =>
      other is Todo &&
      other.id == id &&
      other.text == text &&
      other.done == done;

  @override
  int get hashCode => Object.hash(id, text, done);

  @override
  String toString() => 'Todo($id, $text, done: $done)';
}

/// A project row; `fetchedAt` is stamped by the response that carried it, so a
/// refetched page is visibly newer than the one it replaced.
class Project {
  const Project(
      {required this.id, required this.name, required this.fetchedAt});

  factory Project.fromJson(Map<String, Object?> json) => Project(
        id: json['id']! as int,
        name: json['name']! as String,
        fetchedAt: DateTime.parse(json['fetchedAt']! as String),
      );

  final int id;
  final String name;
  final DateTime fetchedAt;

  @override
  bool operator ==(Object other) =>
      other is Project &&
      other.id == id &&
      other.name == name &&
      other.fetchedAt == fetchedAt;

  @override
  int get hashCode => Object.hash(id, name, fetchedAt);

  @override
  String toString() => 'Project($id)';
}

/// One page of projects, page-numbered (`GET /api/projects?page=`).
class ProjectPage {
  const ProjectPage({
    required this.projects,
    required this.page,
    required this.hasMore,
  });

  factory ProjectPage.fromJson(Map<String, Object?> json) => ProjectPage(
        projects: (json['projects']! as List<Object?>)
            .map((item) => Project.fromJson(item! as Map<String, Object?>))
            .toList(),
        page: json['page']! as int,
        hasMore: json['hasMore']! as bool,
      );

  final List<Project> projects;
  final int page;
  final bool hasMore;

  @override
  bool operator ==(Object other) =>
      other is ProjectPage &&
      listEquals(other.projects, projects) &&
      other.page == page &&
      other.hasMore == hasMore;

  @override
  int get hashCode => Object.hash(Object.hashAll(projects), page, hasMore);

  @override
  String toString() => 'ProjectPage($page, ${projects.length} rows)';
}

/// One slice of projects, cursor-based (`GET /api/projects?cursor=`), with
/// the cursors in both directions or `null` where the data ends.
class ProjectSlice {
  const ProjectSlice({
    required this.items,
    required this.nextId,
    required this.previousId,
  });

  factory ProjectSlice.fromJson(Map<String, Object?> json) => ProjectSlice(
        items: (json['items']! as List<Object?>)
            .map((item) => Project.fromJson(item! as Map<String, Object?>))
            .toList(),
        nextId: json['nextId'] as int?,
        previousId: json['previousId'] as int?,
      );

  final List<Project> items;
  final int? nextId;
  final int? previousId;

  @override
  bool operator ==(Object other) =>
      other is ProjectSlice &&
      listEquals(other.items, items) &&
      other.nextId == nextId &&
      other.previousId == previousId;

  @override
  int get hashCode => Object.hash(Object.hashAll(items), nextId, previousId);

  @override
  String toString() =>
      'ProjectSlice(${items.length} rows, next $nextId, previous $previousId)';
}

/// A tick, one row of the list the auto-refetching screen polls.
class Tick {
  const Tick({required this.id, required this.at});

  factory Tick.fromJson(Map<String, Object?> json) => Tick(
        id: json['id']! as int,
        at: DateTime.parse(json['at']! as String),
      );

  final int id;
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is Tick && other.id == id && other.at == at;

  @override
  int get hashCode => Object.hash(id, at);

  @override
  String toString() => 'Tick($id)';
}

/// What `GET /api/time` answers: the server's clock and a serial that grows
/// by one per call, so "a refetch happened" shows without comparing clocks.
class ServerTime {
  const ServerTime({required this.now, required this.serial});

  factory ServerTime.fromJson(Map<String, Object?> json) => ServerTime(
        now: DateTime.parse(json['now']! as String),
        serial: json['serial']! as int,
      );

  final DateTime now;
  final int serial;

  @override
  bool operator ==(Object other) =>
      other is ServerTime && other.now == now && other.serial == serial;

  @override
  int get hashCode => Object.hash(now, serial);

  @override
  String toString() => 'ServerTime(#$serial)';
}

/// One scripted failure for the backend's `failNext`: the next [count]
/// requests matching [method] and [path] (exact, or a prefix when the path
/// ends in `*`) answer [status].
class FailNext {
  const FailNext({
    required this.method,
    required this.path,
    this.count = 1,
    this.status = 500,
    this.message,
  });

  final String method;
  final String path;
  final int count;
  final int status;
  final String? message;

  Map<String, Object?> toJson() => <String, Object?>{
        'method': method,
        'path': path,
        'count': count,
        'status': status,
        if (message != null) 'message': message,
      };
}
