import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_todo/app.dart';
import 'package:voice_todo/data/app_state.dart';
import 'package:voice_todo/data/store.dart';
import 'package:voice_todo/models/todo.dart';

Future<AppState> pumpApp(
  WidgetTester tester, {
  List<Todo> todos = const <Todo>[],
}) async {
  final AppState state = AppState(InMemoryAppStore(AppSnapshot(todos: todos)));
  await state.init();
  await tester.pumpWidget(VoiceTodoApp(state: state));
  await tester.pumpAndSettle();
  return state;
}

/// Forces the debounced write to happen now.
///
/// Without this the 250 ms save timer is still pending when the test ends, and
/// `testWidgets` fails the test for leaking a timer.
Future<void> settlePersistence(WidgetTester tester, AppState state) async {
  state.flush();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an empty state and the voice action', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('No to-dos yet'), findsOneWidget);
    expect(find.text('Speak'), findsOneWidget);
  });

  testWidgets('adds a to-do through the editor sheet', (
    WidgetTester tester,
  ) async {
    final AppState state = await pumpApp(tester);

    await tester.tap(find.byTooltip('New to-do'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Buy milk');
    await tester.tap(find.text('Add to-do'));
    await tester.pumpAndSettle();

    expect(state.todos.single.title, 'Buy milk');
    expect(find.text('Buy milk'), findsOneWidget);

    await settlePersistence(tester, state);
  });

  testWidgets('completing a to-do moves it under Completed', (
    WidgetTester tester,
  ) async {
    final AppState state = await pumpApp(
      tester,
      todos: <Todo>[
        Todo(id: 'a', title: 'Walk the dog', createdAt: DateTime(2030)),
      ],
    );

    expect(find.text('Walk the dog'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Completed'), findsOneWidget);

    await settlePersistence(tester, state);
  });

  testWidgets('switching to Notes shows the notes empty state', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();

    expect(find.text('No notes yet'), findsOneWidget);
  });

  testWidgets('the voice sheet parses typed input and saves the result', (
    WidgetTester tester,
  ) async {
    final AppState state = await pumpApp(tester);

    await tester.tap(find.text('Speak'));
    await tester.pumpAndSettle();
    expect(find.text('Voice capture'), findsOneWidget);

    // Typing goes through exactly the same parser as speech, which is what
    // makes the app usable on browsers without the Web Speech API.
    await tester.tap(find.text('Type instead'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'add buy milk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Review before saving'), findsOneWidget);

    await tester.tap(find.text('Add 1 item'));
    await tester.pumpAndSettle();

    expect(state.todos.single.title, 'Buy milk');
    expect(find.text('Buy milk'), findsOneWidget);

    await settlePersistence(tester, state);
  });
}
