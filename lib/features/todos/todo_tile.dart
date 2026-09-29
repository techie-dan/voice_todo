import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../data/app_state.dart';
import '../../data/app_state_scope.dart';
import '../../models/priority.dart';
import '../../models/todo.dart';
import 'todo_editor_sheet.dart';

/// One row in the to-do list: complete, open, or swipe away.
class TodoTile extends StatelessWidget {
  const TodoTile({super.key, required this.todo});

  final Todo todo;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    // Captured now: the tile is gone from the tree by the time the callback
    // runs, so the messenger cannot be looked up later.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // Read without subscribing: the list above already subscribes, so a second
    // dependency here would just rebuild every row twice.
    final AppState state = AppStateScope.read(context);

    return Dismissible(
      key: ValueKey<String>(todo.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (DismissDirection _) {
        state.deleteTodo(todo.id);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Deleted “${todo.title}”'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => state.addTodos(<Todo>[todo]),
            ),
          ),
        );
      },
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 6, right: 16),
        leading: Checkbox(
          value: todo.isDone,
          onChanged: (bool? _) => state.toggleTodo(todo.id),
        ),
        title: Text(
          todo.title,
          style: theme.textTheme.bodyLarge?.copyWith(
            decoration: todo.isDone ? TextDecoration.lineThrough : null,
            color: todo.isDone ? scheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: _subtitle(theme),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => TodoEditorSheet.show(context, todo: todo),
      ),
    );
  }

  Widget? _subtitle(ThemeData theme) {
    final List<Widget> chips = <Widget>[
      if (todo.dueAt != null)
        _Pill(
          icon: Icons.schedule,
          label: formatDueLabel(todo.dueAt!),
          emphasized: todo.isOverdue,
        ),
      if (todo.priority != Priority.normal)
        _Pill(
          icon: Icons.flag_outlined,
          label: todo.priority.label,
          emphasized: todo.priority == Priority.high,
        ),
      if (todo.hasDetails) const _Pill(icon: Icons.notes, label: 'Notes'),
    ];

    if (chips.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color background = emphasized
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final Color foreground = emphasized
        ? scheme.onErrorContainer
        : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
