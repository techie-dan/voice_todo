import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/date_format.dart';
import '../core/id.dart';
import '../models/note.dart';
import '../models/priority.dart';
import '../models/todo.dart';
import 'store.dart';

/// Which slice of the to-do list is on screen.
enum TodoFilter {
  all('All'),
  today('Today'),
  upcoming('Upcoming'),
  completed('Done');

  const TodoFilter(this.label);

  final String label;
}

/// The app's single source of truth for todos and notes.
///
/// Widgets read it through `AppStateScope.of(context)` and change it only by
/// calling the methods below; nothing else edits the collections. Every
/// mutation notifies listeners and schedules a debounced write, so callers
/// never save explicitly.
class AppState extends ChangeNotifier {
  AppState(this._store);

  final AppStore _store;

  /// Coalesces bursts of edits — typing in a note, or a voice batch — into a
  /// single write.
  static const Duration saveDebounce = Duration(milliseconds: 250);

  final List<Todo> _todos = <Todo>[];
  final List<Note> _notes = <Note>[];
  Timer? _pendingSave;
  bool _isReady = false;

  bool get isReady => _isReady;

  /// Open and completed items, in display order. Unmodifiable: mutate through
  /// this class, never through the list it returns.
  List<Todo> get todos => List<Todo>.unmodifiable(_todos);

  /// Pinned first, then most recently edited.
  List<Note> get notes => List<Note>.unmodifiable(_notes);

  int get openCount => _todos.where((Todo todo) => !todo.isDone).length;

  int get overdueCount => _todos.where((Todo todo) => todo.isOverdue).length;

  // ---------------------------------------------------------------- lifecycle

  /// Loads persisted data. Called from `main` before the first frame, so the
  /// UI never renders a loading state for data that is already on device.
  Future<void> init() async {
    final AppSnapshot snapshot = await _store.load();
    _todos
      ..clear()
      ..addAll(snapshot.todos);
    _notes
      ..clear()
      ..addAll(snapshot.notes);
    _sortTodos();
    _sortNotes();
    _isReady = true;
    notifyListeners();
  }

  /// Persists any pending change immediately. Called on dispose so a debounced
  /// edit is not lost when the app shuts down.
  void flush() {
    if (_pendingSave == null) return;
    _pendingSave?.cancel();
    _pendingSave = null;
    unawaited(_write());
  }

  @override
  void dispose() {
    flush();
    super.dispose();
  }

  // ------------------------------------------------------------------ queries

  Todo? todoById(String id) {
    for (final Todo todo in _todos) {
      if (todo.id == id) return todo;
    }
    return null;
  }

  Note? noteById(String id) {
    for (final Note note in _notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  /// Items matching [filter] and [query], in display order.
  List<Todo> visibleTodos({
    TodoFilter filter = TodoFilter.all,
    String query = '',
  }) {
    final String needle = query.trim().toLowerCase();
    final DateTime now = DateTime.now();

    bool matchesQuery(Todo todo) =>
        needle.isEmpty ||
        todo.title.toLowerCase().contains(needle) ||
        todo.details.toLowerCase().contains(needle);

    return _todos
        .where((Todo todo) {
          if (!matchesQuery(todo)) return false;
          final DateTime? due = todo.dueAt;
          final bool dueToday =
              due != null && isSameDay(due, now) && !todo.isDone;
          return switch (filter) {
            TodoFilter.all => true,
            // "Today" means needs attention now: due today, or already overdue.
            TodoFilter.today => dueToday || (!todo.isDone && todo.isOverdue),
            TodoFilter.upcoming =>
              !todo.isDone &&
                  due != null &&
                  !isSameDay(due, now) &&
                  due.isAfter(now),
            TodoFilter.completed => todo.isDone,
          };
        })
        .toList(growable: false);
  }

  /// Notes matching [query], in display order.
  List<Note> visibleNotes({String query = ''}) {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) return notes;
    return _notes
        .where(
          (Note note) =>
              note.displayTitle.toLowerCase().contains(needle) ||
              note.body.toLowerCase().contains(needle),
        )
        .toList(growable: false);
  }

  // ------------------------------------------------------------------ to-dos

  void addTodo({
    required String title,
    String details = '',
    DateTime? dueAt,
    Priority priority = Priority.normal,
  }) {
    addTodos(<Todo>[
      Todo(
        id: newId(),
        title: title,
        details: details,
        dueAt: dueAt,
        priority: priority,
        createdAt: DateTime.now(),
      ),
    ]);
  }

  /// Adds a batch — the voice sheet saves a whole utterance at once, so this
  /// notifies and persists once rather than once per item.
  void addTodos(Iterable<Todo> items) {
    final List<Todo> accepted = items
        .where((Todo todo) => todo.title.trim().isNotEmpty)
        .toList(growable: false);
    if (accepted.isEmpty) return;
    _todos.addAll(accepted);
    _sortTodos();
    _changed();
  }

  void updateTodo(Todo updated) {
    final int index = _todos.indexWhere((Todo todo) => todo.id == updated.id);
    if (index == -1) return;
    _todos[index] = updated;
    _sortTodos();
    _changed();
  }

  void toggleTodo(String id) {
    final int index = _todos.indexWhere((Todo todo) => todo.id == id);
    if (index == -1) return;
    _todos[index] = _todos[index].toggled();
    _sortTodos();
    _changed();
  }

  void deleteTodo(String id) {
    final int before = _todos.length;
    _todos.removeWhere((Todo todo) => todo.id == id);
    if (_todos.length != before) _changed();
  }

  void clearCompleted() {
    final int before = _todos.length;
    _todos.removeWhere((Todo todo) => todo.isDone);
    if (_todos.length != before) _changed();
  }

  // ------------------------------------------------------------------- notes

  /// Creates a note and returns it, so the caller can navigate straight into it.
  Note addNote({String title = '', String body = ''}) {
    final DateTime now = DateTime.now();
    final Note note = Note(
      id: newId(),
      title: title,
      body: body,
      createdAt: now,
      updatedAt: now,
    );
    _notes.add(note);
    _sortNotes();
    _changed();
    return note;
  }

  void updateNote(Note updated) {
    final int index = _notes.indexWhere((Note note) => note.id == updated.id);
    if (index == -1) return;
    _notes[index] = updated;
    _sortNotes();
    _changed();
  }

  void toggleNotePin(String id) {
    final int index = _notes.indexWhere((Note note) => note.id == id);
    if (index == -1) return;
    // Deliberately does not touch `updatedAt`: the notes list renders it as
    // "edited 2h ago", and pinning is not an edit. Bumping it here would both
    // display a false timestamp and reorder the note for a reason the user
    // cannot see. The pinned-first rule in _sortNotes is what floats it.
    _notes[index] = _notes[index].copyWith(isPinned: !_notes[index].isPinned);
    _sortNotes();
    _changed();
  }

  void deleteNote(String id) {
    final int before = _notes.length;
    _notes.removeWhere((Note note) => note.id == id);
    if (_notes.length != before) _changed();
  }

  // ----------------------------------------------------------------- private

  void _changed() {
    notifyListeners();
    _pendingSave?.cancel();
    _pendingSave = Timer(saveDebounce, () {
      _pendingSave = null;
      unawaited(_write());
    });
  }

  Future<void> _write() => _store.save(
    AppSnapshot(
      // Copies: encoding happens after an await, and the live lists keep
      // changing underneath it.
      todos: List<Todo>.of(_todos),
      notes: List<Note>.of(_notes),
    ),
  );

  /// Open items first, soonest due date first (undated last), then by priority,
  /// then by creation order. Completed items sink to the bottom, most recently
  /// completed first.
  void _sortTodos() {
    _todos.sort((Todo a, Todo b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      if (a.isDone) {
        final DateTime aDone = a.completedAt ?? a.createdAt;
        final DateTime bDone = b.completedAt ?? b.createdAt;
        return bDone.compareTo(aDone);
      }
      final DateTime? aDue = a.dueAt;
      final DateTime? bDue = b.dueAt;
      if (aDue == null && bDue != null) return 1;
      if (aDue != null && bDue == null) return -1;
      if (aDue != null && bDue != null) {
        final int byDue = aDue.compareTo(bDue);
        if (byDue != 0) return byDue;
      }
      final int byPriority = b.priority.index.compareTo(a.priority.index);
      if (byPriority != 0) return byPriority;
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  void _sortNotes() {
    _notes.sort((Note a, Note b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }
}
