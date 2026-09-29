import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../data/app_state.dart';
import '../../data/app_state_scope.dart';
import '../../models/todo.dart';
import 'todo_tile.dart';

/// The to-do list: filter chips over sectioned rows, with empty states.
class TodoListView extends StatelessWidget {
  const TodoListView({
    super.key,
    required this.query,
    required this.filter,
    required this.onFilterChanged,
  });

  final String query;
  final TodoFilter filter;
  final ValueChanged<TodoFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final List<Todo> items = state.visibleTodos(filter: filter, query: query);

    return Column(
      children: <Widget>[
        _filterBar(context, state),
        Expanded(
          child: items.isEmpty
              ? _EmptyState(hasAnyTodos: state.todos.isNotEmpty)
              : ListView(
                  padding: const EdgeInsets.only(bottom: 120),
                  children: _rows(context, items),
                ),
        ),
      ],
    );
  }

  Widget _filterBar(BuildContext context, AppState state) {
    final bool hasCompleted = state.todos.any((Todo todo) => todo.isDone);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: <Widget>[
          for (final TodoFilter option in TodoFilter.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: FilterChip(
                label: Text(option.label),
                selected: filter == option,
                onSelected: (bool _) => onFilterChanged(option),
              ),
            ),
          if (hasCompleted)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: ActionChip(
                avatar: const Icon(Icons.cleaning_services_outlined, size: 16),
                label: const Text('Clear done'),
                onPressed: state.clearCompleted,
              ),
            ),
        ],
      ),
    );
  }

  /// Under "All" the list is bucketed by urgency; under a specific filter the
  /// filter already says what the grouping would, so rows go in unlabelled.
  List<Widget> _rows(BuildContext context, List<Todo> items) {
    if (filter != TodoFilter.all) {
      return <Widget>[for (final Todo todo in items) TodoTile(todo: todo)];
    }

    final ThemeData theme = Theme.of(context);
    final DateTime now = DateTime.now();
    final List<Todo> overdue = <Todo>[];
    final List<Todo> today = <Todo>[];
    final List<Todo> upcoming = <Todo>[];
    final List<Todo> undated = <Todo>[];
    final List<Todo> completed = <Todo>[];

    for (final Todo todo in items) {
      final DateTime? due = todo.dueAt;
      if (todo.isDone) {
        completed.add(todo);
      } else if (due == null) {
        undated.add(todo);
      } else if (todo.isOverdue) {
        overdue.add(todo);
      } else if (isSameDay(due, now)) {
        today.add(todo);
      } else {
        upcoming.add(todo);
      }
    }

    final List<Widget> rows = <Widget>[];
    void addSection(String label, List<Todo> todos) {
      if (todos.isEmpty) return;
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
          child: Text(
            '$label · ${todos.length}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      rows.addAll(todos.map((Todo todo) => TodoTile(todo: todo)));
    }

    addSection('Overdue', overdue);
    addSection('Today', today);
    addSection('Upcoming', upcoming);
    addSection('No due date', undated);
    addSection('Completed', completed);
    return rows;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAnyTodos});

  final bool hasAnyTodos;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              hasAnyTodos ? Icons.search_off : Icons.mic_none,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              hasAnyTodos ? 'Nothing here' : 'No to-dos yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              hasAnyTodos
                  ? 'No to-dos match this view. Try clearing the search or '
                        'picking another filter.'
                  : 'Tap Speak and describe what you need to do — for example '
                        '“add buy milk tomorrow at 9am”.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
