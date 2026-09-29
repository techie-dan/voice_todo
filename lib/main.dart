import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_state.dart';
import 'data/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppState state = AppState(SharedPreferencesAppStore());
  // Load before the first frame. The store is local and small, so there is no
  // loading state to design and no flash of empty UI.
  await state.init();

  runApp(VoiceTodoApp(state: state));
}
