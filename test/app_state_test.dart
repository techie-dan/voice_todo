import 'package:flutter_test/flutter_test.dart';
import 'package:voice_todo/data/app_state.dart';
import 'package:voice_todo/data/store.dart';
import 'package:voice_todo/models/note.dart';
import 'package:voice_todo/models/priority.dart';
import 'package:voice_todo/models/todo.dart';

Future<AppState> readyState([InMemoryAppStore? store]) async {
  final AppState state = AppState(store ?? InMemoryAppStore());
  await state.init();
  return state;
}

List<String> titlesOf(List<Todo> todos) =>
    todos.map((Todo todo) => todo.title).toList();

void main() {
  group('to-dos', () {
    test('orders open items by due date, undated last', () async {
      final AppState state = await readyState();
      state.addTodo(title: 'later', dueAt: DateTime(2030, 1, 2));
      state.addTodo(title: 'sooner', dueAt: DateTime(2030, 1, 1));
      state.addTodo(title: 'undated');
      expect(titlesOf(state.todos), <String>['sooner', 'later', 'undated']);
    });

    test('orders by priority when due dates tie', () async {
      final AppState state = await readyState();
      final DateTime due = DateTime(2030, 1, 1);
      state.addTodo(title: 'low', dueAt: due, priority: Priority.low);
      state.addTodo(title: 'high', dueAt: due, priority: Priority.high);
      state.addTodo(title: 'normal', dueAt: due);
      expect(titlesOf(state.todos), <String>['high', 'normal', 'low']);
    });

    test('ignores blank titles', () async {
      final AppState state = await readyState();
      state.addTodo(title: '   ');
      state.addTodos(<Todo>[
        Todo(id: 'x', title: '', createdAt: DateTime(2025)),
      ]);
      expect(state.todos, isEmpty);
    });

    test('toggling stamps and clears the completion time', () async {
      final AppState state = await readyState();
      state.addTodo(title: 'ship it');
      final String id = state.todos.single.id;

      state.toggleTodo(id);
      expect(state.todos.single.isDone, isTrue);
      expect(state.todos.single.completedAt, isNotNull);

      state.toggleTodo(id);
      expect(state.todos.single.isDone, isFalse);
      expect(state.todos.single.completedAt, isNull);
    });

    test('completed items sink below open ones', () async {
      final AppState state = await readyState();
      state.addTodo(title: 'open');
      state.addTodo(title: 'closing');
      state.toggleTodo(
        state.todos.firstWhere((Todo t) => t.title == 'closing').id,
      );
      expect(titlesOf(state.todos), <String>['open', 'closing']);
    });

    test('update replaces in place', () async {
      final AppState state = await readyState();
      state.addTodo(title: 'draft');
      final Todo original = state.todos.single;
      state.updateTodo(
        original.copyWith(title: 'final', details: 'with detail'),
      );
      expect(state.todos.single.title, 'final');
      expect(state.todos.single.details, 'with detail');
      expect(state.todos.single.id, original.id);
    });

    test('update ignores an unknown id', () async {
      final AppState state = await readyState();
      state.updateTodo(
        Todo(id: 'ghost', title: 'nothing', createdAt: DateTime(2025)),
      );
      expect(state.todos, isEmpty);
    });

    test('clearCompleted keeps open items', () async {
      final AppState state = await readyState();
      state.addTodo(title: 'keep');
      state.addTodo(title: 'drop');
      state.toggleTodo(
        state.todos.firstWhere((Todo t) => t.title == 'drop').id,
      );
      state.clearCompleted();
      expect(titlesOf(state.todos), <String>['keep']);
    });
  });

  group('filters', () {
    late AppState state;
    late DateTime now;

    setUp(() async {
      state = await readyState();
      now = DateTime.now();
      state.addTodo(
        title: 'overdue',
        dueAt: now.subtract(const Duration(days: 1)),
      );
      state.addTodo(
        title: 'due today',
        dueAt: DateTime(now.year, now.month, now.day, 12),
      );
      state.addTodo(title: 'later', dueAt: now.add(const Duration(days: 3)));
      state.addTodo(title: 'someday');
      state.addTodo(title: 'finished');
      state.toggleTodo(
        state.todos.firstWhere((Todo t) => t.title == 'finished').id,
      );
    });

    test('today covers what needs attention now', () {
      final List<String> titles = titlesOf(
        state.visibleTodos(filter: TodoFilter.today),
      );
      expect(titles, contains('due today'));
      expect(titles, contains('overdue'));
      expect(titles, isNot(contains('later')));
    });

    test('upcoming holds only future, dated, open items', () {
      expect(
        titlesOf(state.visibleTodos(filter: TodoFilter.upcoming)),
        <String>['later'],
      );
    });

    test('completed holds only done items', () {
      expect(
        titlesOf(state.visibleTodos(filter: TodoFilter.completed)),
        <String>['finished'],
      );
    });

    test('all holds everything', () {
      expect(state.visibleTodos().length, 5);
    });

    test('search matches the title', () {
      expect(titlesOf(state.visibleTodos(query: 'over')), <String>['overdue']);
      expect(state.visibleTodos(query: 'nothing here'), isEmpty);
    });
  });

  group('notes', () {
    test('add returns the created note', () async {
      final AppState state = await readyState();
      final Note note = state.addNote(title: 'Ideas', body: 'something');
      expect(state.notes.single.id, note.id);
      expect(state.noteById(note.id)?.title, 'Ideas');
    });

    test('pinned notes sort first, then by last edited', () async {
      final AppState state = await readyState();
      final Note first = state.addNote(title: 'first');
      final Note second = state.addNote(title: 'second');
      state.toggleNotePin(first.id);
      expect(state.notes.map((Note n) => n.title), <String>['first', 'second']);

      // Unpinned, the most recently edited wins.
      state.toggleNotePin(first.id);
      state.updateNote(second.copyWith(title: 'second', body: 'edited'));
      expect(state.notes.first.title, 'second');
    });

    test('delete removes the note', () async {
      final AppState state = await readyState();
      final Note note = state.addNote(title: 'temp');
      state.deleteNote(note.id);
      expect(state.notes, isEmpty);
    });
  });

  group('persistence', () {
    test('coalesces a burst of edits into one write', () async {
      final InMemoryAppStore store = InMemoryAppStore();
      final AppState state = await readyState(store);
      state.addTodo(title: 'one');
      state.addTodo(title: 'two');
      state.addTodo(title: 'three');
      expect(store.saveCount, 0); // still inside the debounce window
      state.flush();
      expect(store.saveCount, 1);
    });

    test('reloads what it saved', () async {
      final InMemoryAppStore store = InMemoryAppStore();
      final AppState first = await readyState(store);
      first.addTodo(title: 'durable');
      first.addNote(title: 'kept');
      first.flush();

      final AppState second = await readyState(store);
      expect(titlesOf(second.todos), <String>['durable']);
      expect(second.notes.single.title, 'kept');
    });
  });
}
