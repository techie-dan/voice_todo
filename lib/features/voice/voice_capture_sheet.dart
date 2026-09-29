import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../core/id.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/app_state_scope.dart';
import '../../models/priority.dart';
import '../../models/todo.dart';
import 'speech_service.dart';
import 'voice_parser.dart';

/// Voice capture sheet: speak (or type) a sentence, review what was understood,
/// then save.
///
/// The review step is the point of the design. Speech recognition and rule-based
/// parsing are both lossy, so nothing is written to [AppState] until the user
/// has seen it and had the chance to edit, deselect or drop each item.
class VoiceCaptureSheet extends StatefulWidget {
  const VoiceCaptureSheet({super.key});

  /// Opens the sheet. Returns when the sheet closes.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) => const VoiceCaptureSheet(),
    );
  }

  @override
  State<VoiceCaptureSheet> createState() => _VoiceCaptureSheetState();
}

class _VoiceCaptureSheetState extends State<VoiceCaptureSheet> {
  final SpeechService _speech = SpeechService();
  final TextEditingController _typedController = TextEditingController();

  List<_EditableTask> _items = <_EditableTask>[];
  ParsedNote? _note;
  bool _saveNote = false;

  String _transcript = '';
  bool _listening = false;
  bool _hasParsed = false;
  bool _typeInstead = false;

  /// Null until the engine has been asked. Deliberately lazy: on web,
  /// initialising prompts for the microphone, and that prompt belongs on a tap.
  bool? _speechReady;
  String? _errorMessage;

  @override
  void dispose() {
    _typedController.dispose();
    for (final _EditableTask item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ capture

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      _parseTranscript();
      return;
    }

    final bool ready = await _speech.initialize(
      statusListener: (String status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _listening = false);
          _parseTranscript();
        }
      },
      errorListener: (String message) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _errorMessage = message;
        });
        _parseTranscript();
      },
    );

    if (!mounted) return;
    setState(() {
      _speechReady = ready;
      if (!ready) _typeInstead = true;
    });
    if (!ready) return;

    setState(() {
      _listening = true;
      _errorMessage = null;
      _transcript = '';
      _hasParsed = false;
    });

    await _speech.start(
      onResult: (String words, bool isFinal) {
        if (!mounted) return;
        setState(() {
          _transcript = words;
          if (isFinal) _listening = false;
        });
        if (isFinal) _parseTranscript();
      },
    );

    if (mounted && _speech.isListening) setState(() => _listening = true);
  }

  void _parseTranscript() {
    final String text = _transcript.trim();
    if (text.isEmpty || _hasParsed) return;
    _applyParse(const VoiceParser().parse(text));
  }

  void _parseTyped() {
    final String text = _typedController.text.trim();
    if (text.isEmpty) return;
    setState(() => _transcript = text);
    _applyParse(const VoiceParser().parse(text));
  }

  void _applyParse(VoiceParseResult result) {
    for (final _EditableTask item in _items) {
      item.dispose();
    }
    setState(() {
      _items = result.tasks.map(_EditableTask.new).toList(growable: true);
      _note = result.note;
      _saveNote = result.note != null;
      _hasParsed = !result.isEmpty;
      _listening = false;
    });
    if (result.isEmpty) {
      setState(() {
        _errorMessage = 'Nothing to add — try saying "add buy milk tomorrow".';
      });
    }
  }

  void _startOver() {
    for (final _EditableTask item in _items) {
      item.dispose();
    }
    setState(() {
      _items = <_EditableTask>[];
      _note = null;
      _saveNote = false;
      _hasParsed = false;
      _transcript = '';
      _errorMessage = null;
      _typedController.clear();
    });
  }

  void _removeItem(_EditableTask item) {
    setState(() => _items.remove(item));
    // Dispose after the frame: the row's TextField is still attached to the
    // controller while this build unwinds.
    WidgetsBinding.instance.addPostFrameCallback((_) => item.dispose());
  }

  void _save() {
    final AppState state = AppStateScope.read(context);
    final DateTime now = DateTime.now();

    final List<Todo> todos = <Todo>[
      for (final _EditableTask item in _items)
        if (item.selected && item.controller.text.trim().isNotEmpty)
          Todo(
            id: newId(),
            title: item.controller.text.trim(),
            dueAt: item.task.dueAt,
            priority: item.task.priority,
            createdAt: now,
          ),
    ];
    state.addTodos(todos);

    final ParsedNote? note = _note;
    if (note != null && _saveNote) {
      state.addNote(title: note.title, body: note.body);
    }

    Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------- ui

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int selectedCount = _items
        .where((_EditableTask item) => item.selected)
        .length;
    final int totalCount = selectedCount + (_note != null && _saveNote ? 1 : 0);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.graphic_eq, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Voice capture',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[_buildBody(theme)],
                ),
              ),
            ),
            if (_hasParsed) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  TextButton.icon(
                    onPressed: _startOver,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Start over'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: totalCount == 0 ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(
                      totalCount == 1 ? 'Add 1 item' : 'Add $totalCount items',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!_hasParsed) _micPanel(theme),
        if (_transcript.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _transcriptCard(theme),
        ],
        if (_errorMessage != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (_hasParsed) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            'Review before saving',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final _EditableTask item in _items) _taskRow(item, theme),
          if (_note != null) _noteCard(theme),
          const SizedBox(height: 4),
          Text(
            'Uncheck anything you do not want, or edit the text inline.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _micPanel(ThemeData theme) {
    return Column(
      children: <Widget>[
        const SizedBox(height: 4),
        Semantics(
          button: true,
          label: _listening ? 'Stop listening' : 'Start voice capture',
          child: SizedBox(
            height: 128,
            width: 128,
            child: FilledButton(
              onPressed: _toggleListening,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                backgroundColor: _listening
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              child: Icon(
                _listening ? Icons.stop : Icons.mic,
                size: 52,
                semanticLabel: _listening
                    ? 'Stop listening'
                    : 'Start listening',
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _listening ? 'Listening…' : 'Tap and describe your to-dos',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'For example: “add buy milk and call mom tomorrow at 3pm”',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (_speechReady == false) ...<Widget>[
          const SizedBox(height: 10),
          _hintCard(
            theme,
            'Speech recognition is not available here. Type your to-dos '
            'instead — they are parsed the same way.',
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _typeInstead = !_typeInstead),
            icon: Icon(_typeInstead ? Icons.mic_none : Icons.keyboard),
            label: Text(_typeInstead ? 'Use the microphone' : 'Type instead'),
          ),
        ),
        if (_typeInstead) ...<Widget>[
          const SizedBox(height: 4),
          TextField(
            controller: _typedController,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            onSubmitted: (String _) => _parseTyped(),
            decoration: InputDecoration(
              hintText: 'add buy milk and call mom tomorrow at 3pm',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Parse',
                icon: const Icon(Icons.arrow_forward),
                onPressed: _parseTyped,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _transcriptCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      child: Text(
        _transcript,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontStyle: _listening ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }

  Widget _taskRow(_EditableTask item, ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
        child: Row(
          children: <Widget>[
            Checkbox(
              value: item.selected,
              onChanged: (bool? value) =>
                  setState(() => item.selected = value ?? false),
            ),
            Expanded(
              child: TextField(
                controller: item.controller,
                style: theme.textTheme.bodyLarge,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText: 'Task',
                ),
              ),
            ),
            if (item.task.dueAt != null) ...<Widget>[
              const SizedBox(width: 6),
              _pill(theme, Icons.schedule, formatDueLabel(item.task.dueAt!)),
            ],
            if (item.task.priority != Priority.normal) ...<Widget>[
              const SizedBox(width: 6),
              _pill(
                theme,
                Icons.priority_high,
                item.task.priority.label,
                highlight: item.task.priority == Priority.high,
              ),
            ],
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => _removeItem(item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noteCard(ThemeData theme) {
    final ParsedNote note = _note!;
    return Card(
      elevation: 0,
      color: theme.colorScheme.secondaryContainer,
      margin: const EdgeInsets.only(top: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      child: CheckboxListTile(
        value: _saveNote,
        onChanged: (bool? value) => setState(() => _saveNote = value ?? false),
        title: Row(
          children: <Widget>[
            const Icon(Icons.sticky_note_2_outlined, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(note.title)),
          ],
        ),
        subtitle: Text(note.body, maxLines: 3, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _pill(
    ThemeData theme,
    IconData icon,
    String label, {
    bool highlight = false,
  }) {
    final Color foreground = highlight
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surface,
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

  Widget _hintCard(ThemeData theme, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: theme.textTheme.bodySmall),
    );
  }
}

/// A parsed task plus the editable controller backing its row.
class _EditableTask {
  _EditableTask(this.task)
    : controller = TextEditingController(text: task.title);

  final ParsedTask task;
  final TextEditingController controller;
  bool selected = true;

  void dispose() => controller.dispose();
}
