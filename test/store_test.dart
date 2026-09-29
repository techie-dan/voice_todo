import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_todo/data/store.dart';
import 'package:voice_todo/models/note.dart';
import 'package:voice_todo/models/priority.dart';
import 'package:voice_todo/models/todo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('model serialisation', () {
    test('a to-do round-trips through JSON', () {
      final Todo original = Todo(
        id: 'abc',
        title: 'Buy milk',
        details: 'semi-skimmed',
        dueAt: DateTime(2030, 1, 1, 9),
        priority: Priority.high,
        isDone: true,
        completedAt: DateTime(2030, 1, 2, 8),
        createdAt: DateTime(2029, 12, 31, 12),
      );
      final Todo restored = Todo.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.details, original.details);
      expect(restored.dueAt, original.dueAt);
      expect(restored.priority, Priority.high);
      expect(restored.isDone, isTrue);
      expect(restored.completedAt, original.completedAt);
      expect(restored.createdAt, original.createdAt);
    });

    test('a to-do survives a corrupt record', () {
      // Every field is the wrong type. Nothing may throw: one damaged entry
      // must not cost the user the rest of their list.
      final Todo restored = Todo.fromJson(<String, Object?>{
        'id': 42,
        'title': null,
        'details': <String>[],
        'isDone': 'yes',
        'priority': 'nonsense',
        'dueAt': 'not a date',
        'createdAt': false,
      });

      expect(restored.title, isEmpty);
      expect(restored.details, isEmpty);
      expect(restored.isDone, isFalse);
      expect(restored.priority, Priority.normal);
      expect(restored.dueAt, isNull);
      expect(restored.id, isNotEmpty); // a fresh id is generated
      expect(restored.createdAt, isNotNull);
    });

    test('a note round-trips through JSON', () {
      final Note original = Note(
        id: 'n1',
        title: 'Wifi',
        body: 'hunter2',
        isPinned: true,
        createdAt: DateTime(2030, 3, 1, 10),
        updatedAt: DateTime(2030, 3, 2, 11),
      );
      final Note restored = Note.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.body, original.body);
      expect(restored.isPinned, isTrue);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('an untitled note borrows its body for display', () {
      final Note note = Note(
        id: 'n2',
        body: 'call the plumber about the radiator',
        createdAt: DateTime(2030),
        updatedAt: DateTime(2030),
      );
      expect(note.displayTitle, 'call the plumber about the radiator');
      expect(
        Note(
          id: 'n3',
          body: 'x' * 100,
          createdAt: DateTime(2030),
          updatedAt: DateTime(2030),
        ).displayTitle,
        endsWith('…'),
      );
    });
  });

  group('SharedPreferencesAppStore', () {
    test('loads empty when nothing has been written', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AppSnapshot snapshot = await SharedPreferencesAppStore().load();
      expect(snapshot.todos, isEmpty);
      expect(snapshot.notes, isEmpty);
    });

    test('returns an empty list for an unparseable document', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SharedPreferencesAppStore.todosKey: 'this is not json',
        SharedPreferencesAppStore.notesKey: '{"not":"a list"}',
      });
      final AppSnapshot snapshot = await SharedPreferencesAppStore().load();
      expect(snapshot.todos, isEmpty);
      expect(snapshot.notes, isEmpty);
    });

    test('drops records that carry no content', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SharedPreferencesAppStore.todosKey: '[{"id":"a","title":"  "}]',
        SharedPreferencesAppStore.notesKey: '[{"id":"b","body":"  "}]',
      });
      final AppSnapshot snapshot = await SharedPreferencesAppStore().load();
      expect(snapshot.todos, isEmpty);
      expect(snapshot.notes, isEmpty);
    });

    test('round-trips through real storage', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferencesAppStore store = SharedPreferencesAppStore();

      await store.save(
        AppSnapshot(
          todos: <Todo>[
            Todo(
              id: 't1',
              title: 'Buy milk',
              dueAt: DateTime(2030, 1, 1, 9),
              priority: Priority.high,
              createdAt: DateTime(2029, 12, 31),
            ),
          ],
          notes: <Note>[
            Note(
              id: 'n1',
              title: 'Wifi',
              body: 'hunter2',
              createdAt: DateTime(2029, 12, 31),
              updatedAt: DateTime(2029, 12, 31),
            ),
          ],
        ),
      );

      final AppSnapshot loaded = await store.load();
      expect(loaded.todos.single.title, 'Buy milk');
      expect(loaded.todos.single.priority, Priority.high);
      expect(loaded.todos.single.dueAt, DateTime(2030, 1, 1, 9));
      expect(loaded.notes.single.body, 'hunter2');
    });
  });
}
