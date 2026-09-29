import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/app_state_scope.dart';
import '../../models/note.dart';
import '../notes/note_editor_page.dart';
import '../notes/notes_view.dart';
import '../todos/todo_editor_sheet.dart';
import '../todos/todo_list_view.dart';
import '../voice/voice_capture_sheet.dart';

/// Root scaffold: to-dos and notes, one shared search field, and the voice
/// capture button.
///
/// Ephemeral UI state — which tab, whether search is open, the query, the
/// selected filter — lives here rather than in [AppState], because none of it
/// needs to survive a restart.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const int _todosTab = 0;
  static const int _notesTab = 1;

  final TextEditingController _searchController = TextEditingController();

  int _tab = _todosTab;
  bool _searching = false;
  String _query = '';
  TodoFilter _filter = TodoFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  void _createForCurrentTab() {
    if (_tab == _notesTab) {
      final Note note = AppStateScope.read(context).addNote();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => NoteEditorPage(note: note),
        ),
      );
      return;
    }
    TodoEditorSheet.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final bool isTodos = _tab == _todosTab;

    return Scaffold(
      appBar: AppBar(
        title: Text(isTodos ? 'To-dos' : 'Notes'),
        actions: <Widget>[
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.search_off : Icons.search),
            onPressed: _toggleSearch,
          ),
          IconButton(
            tooltip: isTodos ? 'New to-do' : 'New note',
            icon: const Icon(Icons.add),
            onPressed: _createForCurrentTab,
          ),
        ],
        bottom: _searching
            ? PreferredSize(
                preferredSize: const Size.fromHeight(68),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (String value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isTodos ? 'Search to-dos' : 'Search notes',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: IndexedStack(
        index: _tab,
        children: <Widget>[
          TodoListView(
            query: _query,
            filter: _filter,
            onFilterChanged: (TodoFilter filter) =>
                setState(() => _filter = filter),
          ),
          NotesView(query: _query),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => VoiceCaptureSheet.show(context),
        tooltip: 'Capture to-dos by voice',
        icon: const Icon(Icons.mic),
        label: const Text('Speak'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (int index) => setState(() => _tab = index),
        destinations: <Widget>[
          NavigationDestination(
            icon: Badge.count(
              count: state.openCount,
              isLabelVisible: state.openCount > 0,
              child: const Icon(Icons.checklist_outlined),
            ),
            selectedIcon: Badge.count(
              count: state.openCount,
              isLabelVisible: state.openCount > 0,
              child: const Icon(Icons.checklist),
            ),
            label: 'To-dos',
          ),
          const NavigationDestination(
            icon: Icon(Icons.sticky_note_2_outlined),
            selectedIcon: Icon(Icons.sticky_note_2),
            label: 'Notes',
          ),
        ],
      ),
    );
  }
}
