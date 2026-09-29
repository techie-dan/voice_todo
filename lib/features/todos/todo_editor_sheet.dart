import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../data/app_state.dart';
import '../../data/app_state_scope.dart';
import '../../models/priority.dart';
import '../../models/todo.dart';

/// Create or edit a to-do.
///
/// The caller hands in the [Todo] it already has (or null to create one), so
/// the sheet never has to look an item up and can never edit a stale copy.
class TodoEditorSheet extends StatefulWidget {
  const TodoEditorSheet({super.key, this.todo});

  final Todo? todo;

  static Future<void> show(BuildContext context, {Todo? todo}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) => TodoEditorSheet(todo: todo),
    );
  }

  @override
  State<TodoEditorSheet> createState() => _TodoEditorSheetState();
}

class _TodoEditorSheetState extends State<TodoEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _details;
  late DateTime? _dueAt;
  late Priority _priority;

  bool get _isEditing => widget.todo != null;

  @override
  void initState() {
    super.initState();
    final Todo? todo = widget.todo;
    _title = TextEditingController(text: todo?.title ?? '');
    _details = TextEditingController(text: todo?.details ?? '');
    _dueAt = todo?.dueAt;
    _priority = todo?.priority ?? Priority.normal;
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  void _save() {
    final String title = _title.text.trim();
    if (title.isEmpty) return;
    final AppState state = AppStateScope.read(context);
    final Todo? existing = widget.todo;

    if (existing == null) {
      state.addTodo(
        title: title,
        details: _details.text.trim(),
        dueAt: _dueAt,
        priority: _priority,
      );
    } else {
      state.updateTodo(
        existing.copyWith(
          title: title,
          details: _details.text.trim(),
          priority: _priority,
          dueAt: _dueAt,
          // copyWith treats null as "leave alone", so clearing needs saying.
          clearDueAt: _dueAt == null,
        ),
      );
    }
    Navigator.of(context).pop();
  }

  void _delete() {
    final Todo? existing = widget.todo;
    if (existing == null) return;
    AppStateScope.read(context).deleteTodo(existing.id);
    Navigator.of(context).pop();
  }

  Future<void> _pickDueDate() async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: _dueAt == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(_dueAt!),
    );
    if (!mounted) return;

    setState(() {
      _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 9,
        time?.minute ?? 0,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _isEditing ? 'Edit to-do' : 'New to-do',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              onSubmitted: (String _) => _save(),
              decoration: const InputDecoration(
                labelText: 'What needs doing?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _details,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Icon(
                  Icons.schedule,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _dueAt == null ? 'No due date' : formatDueLabel(_dueAt!),
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                if (_dueAt != null)
                  IconButton(
                    tooltip: 'Clear due date',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _dueAt = null),
                  ),
                TextButton(
                  onPressed: _pickDueDate,
                  child: Text(_dueAt == null ? 'Set date' : 'Change'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Priority',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<Priority>(
              segments: <ButtonSegment<Priority>>[
                for (final Priority priority in Priority.values)
                  ButtonSegment<Priority>(
                    value: priority,
                    label: Text(priority.label),
                  ),
              ],
              selected: <Priority>{_priority},
              onSelectionChanged: (Set<Priority> selection) =>
                  setState(() => _priority = selection.first),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                if (_isEditing)
                  TextButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: Text(_isEditing ? 'Save' : 'Add to-do'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
