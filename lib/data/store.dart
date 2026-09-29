import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/json_utils.dart';
import '../models/note.dart';
import '../models/todo.dart';

/// Everything the app persists, in one value.
class AppSnapshot {
  const AppSnapshot({this.todos = const <Todo>[], this.notes = const <Note>[]});

  final List<Todo> todos;
  final List<Note> notes;
}

/// The persistence boundary.
///
/// Only implementers know how data is stored. Moving to SQLite for scale, or
/// to a sync backend for multi-device, means writing one new implementation
/// and changing the single construction site in `main.dart`. Nothing else in
/// the app may depend on the storage engine.
abstract class AppStore {
  Future<AppSnapshot> load();

  Future<void> save(AppSnapshot snapshot);
}

/// Key/value implementation backed by `shared_preferences`, the one store that
/// works unchanged on Android, iOS and web (localStorage).
///
/// Each collection is one JSON document. That is the right trade for a personal
/// to-do list: the dataset is small, writes are debounced by [AppState], and
/// there is no schema or migration machinery to maintain.
class SharedPreferencesAppStore implements AppStore {
  static const String todosKey = 'voice_todo.todos.v1';
  static const String notesKey = 'voice_todo.notes.v1';

  @override
  Future<AppSnapshot> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return AppSnapshot(
      todos: _decode(prefs.getString(todosKey), Todo.fromJson)
          .where((Todo todo) => todo.title.trim().isNotEmpty)
          .toList(growable: false),
      notes: _decode(
        prefs.getString(notesKey),
        Note.fromJson,
      ).where((Note note) => !note.isEmpty).toList(growable: false),
    );
  }

  @override
  Future<void> save(AppSnapshot snapshot) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      todosKey,
      jsonEncode(snapshot.todos.map((Todo todo) => todo.toJson()).toList()),
    );
    await prefs.setString(
      notesKey,
      jsonEncode(snapshot.notes.map((Note note) => note.toJson()).toList()),
    );
  }

  /// Decodes one document, returning an empty list rather than throwing when
  /// the payload is missing or damaged: a corrupt store must not brick the app.
  /// Records that fail the model's own shape check are dropped by the caller's
  /// `where`, so one bad entry costs one entry.
  List<T> _decode<T>(String? raw, T Function(Map<String, Object?>) parse) {
    if (raw == null || raw.isEmpty) return <T>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <T>[];
      return decoded.map(readMap).map(parse).toList(growable: false);
    } on FormatException {
      return <T>[];
    }
  }
}

/// In-memory store for tests, and for running the app without touching disk.
class InMemoryAppStore implements AppStore {
  InMemoryAppStore([this._snapshot = const AppSnapshot()]);

  AppSnapshot _snapshot;

  /// Number of writes performed — lets tests assert on debounced persistence.
  int saveCount = 0;

  @override
  Future<AppSnapshot> load() async => _snapshot;

  @override
  Future<void> save(AppSnapshot snapshot) async {
    _snapshot = snapshot;
    saveCount++;
  }
}
