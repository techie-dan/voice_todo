import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// Provides [AppState] to the widget tree and rebuilds dependents when it
/// changes.
///
/// `InheritedNotifier` gives the subscription for free: a widget that calls
/// [AppStateScope.of] in `build` re-runs whenever the notifier fires, so no
/// state-management package is needed for an app this size.
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  /// Reads the state and subscribes the calling widget to its changes.
  /// Use in `build`.
  static AppState of(BuildContext context) {
    final AppStateScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(
      scope != null,
      'AppStateScope.of() requires an AppStateScope above this context.',
    );
    return scope!.notifier!;
  }

  /// Reads the state *without* subscribing. Use inside callbacks, where a
  /// dependency would cause the calling widget to rebuild for nothing.
  static AppState read(BuildContext context) {
    final AppStateScope? scope = context
        .getInheritedWidgetOfExactType<AppStateScope>();
    assert(
      scope != null,
      'AppStateScope.read() requires an AppStateScope above this context.',
    );
    return scope!.notifier!;
  }
}
