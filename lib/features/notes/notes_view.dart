import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/app_state_scope.dart';
import '../../models/note.dart';
import 'note_editor_page.dart';

/// The notes tab: pinned first, then most recently edited.
class NotesView extends StatelessWidget {
  const NotesView({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final List<Note> notes = state.visibleNotes(query: query);

    if (notes.isEmpty) {
      return _EmptyNotes(hasAnyNotes: state.notes.isNotEmpty);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
      itemCount: notes.length,
      itemBuilder: (BuildContext context, int index) =>
          _NoteCard(note: notes[index]),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppState state = AppStateScope.read(context);
    final BorderRadius radius = BorderRadius.circular(kCardRadius);
    final bool hasTitle = note.title.trim().isNotEmpty;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: InkWell(
        borderRadius: radius,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext _) => NoteEditorPage(note: note),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      note.displayTitle,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Only preview the body when it is not already standing in
                    // for the title.
                    if (hasTitle && note.preview.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        note.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      formatRelative(note.updatedAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: note.isPinned ? 'Unpin note' : 'Pin note',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 18,
                  color: note.isPinned
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                onPressed: () => state.toggleNotePin(note.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes({required this.hasAnyNotes});

  final bool hasAnyNotes;

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
              Icons.sticky_note_2_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              hasAnyNotes ? 'No notes match' : 'No notes yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              hasAnyNotes
                  ? 'Try a different search.'
                  : 'Tap + to write one, or say “take a note: …” and capture '
                        'it by voice.',
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
