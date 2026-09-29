import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'data/app_state.dart';
import 'data/app_state_scope.dart';
import 'features/home/home_shell.dart';

/// Root widget. Owns the theme and publishes [AppState] to the tree.
class VoiceTodoApp extends StatelessWidget {
  const VoiceTodoApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: state,
      child: MaterialApp(
        title: 'Voice To-Do',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const HomeShell(),
      ),
    );
  }
}
