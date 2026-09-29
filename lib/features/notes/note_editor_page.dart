import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/app_state_scope.dart';
import '../../models/note.dart';

/// Full-screen note editor. Edits save as you type.
///
/// The caller passes the [Note] it already has, so the page has something to
/// render on its first frame without a lookup.
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key, required this.note});

  final Note note;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  static const Duration _saveDebounce = Duration(milliseconds: 400);

  late final TextEditingController _title;
  late final TextEditingController _body;

  /// Captured in [didChangeDependencies] so [dispose] can still reach it.
  AppState? _state;
  Timer? _saveTimer;
  bool _dirty = false;
  late bool _pinned;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    _body = TextEditingController(text: widget.note.body);
    _pinned = widget.note.isPinned;
    _title.addListener(_onChanged);
    _body.addListener(_onChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state = AppStateScope.of(context);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _title.removeListener(_onChanged);
    _body.removeListener(_onChanged);

    final AppState? state = _state;
    if (state != null) {
      final String id = widget.note.id;
      final String title = _title.text;
      final String body = _body.text;
      final bool dirty = _dirty;
      // Deferred: notifying listeners while the route is being torn down would
      // rebuild the tab underneath mid-teardown.
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        final Note? current = state.noteById(id);
        if (current == null) return;
        if (title.trim().isEmpty && body.trim().isEmpty) {
          // A note that was created and abandoned without a word in it.
          state.deleteNote(id);
          return;
        }
        if (dirty) {
          state.updateNote(current.edited(title: title, body: body));
        }
      });
    }

    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _onChanged() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, _saveNow);
  }

  void _saveNow() {
    final AppState? state = _state;
    if (state == null) return;
    final Note? current = state.noteById(widget.note.id);
    if (current == null) return;
    state.updateNote(current.edited(title: _title.text, body: _body.text));
    _dirty = false;
  }

  void _togglePin() {
    final AppState? state = _state;
    if (state == null) return;
    // Persist the text first: the pin toggle re-reads the stored note.
    if (_dirty) _saveNow();
    setState(() => _pinned = !_pinned);
    state.toggleNotePin(widget.note.id);
  }

  Future<void> _delete() async {
    final AppState? state = _state;
    if (state == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete this note?'),
        content: const Text('This cannot be undone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _saveTimer?.cancel();
    _dirty = false;
    state.deleteNote(widget.note.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Note'),
        actions: <Widget>[
          IconButton(
            tooltip: _pinned ? 'Unpin note' : 'Pin note',
            icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
            onPressed: _togglePin,
          ),
          IconButton(
            tooltip: 'Delete note',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.headlineSmall,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Title',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _body,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                textAlignVertical: TextAlignVertical.top,
                style: theme.textTheme.bodyLarge,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Start writing…',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
