# AGENTS.md

Operating guide for AI agents (and humans) working in this repository.
Read this before making changes. It is the contract for how the project is
structured and how work should be done here.

---

## 1. What this project is

A **voice-first to-do list and notes app** built with Flutter. It runs as a
native app (Android/iOS) and as a web app from a single codebase.

Three user-facing capabilities:

1. **To-dos** — create, edit, complete, schedule (due dates), prioritise, search, filter.
2. **Notes** — free-form notes with pinning, kept alongside the to-do list.
3. **Voice capture** — the signature feature. The user speaks a sentence
   ("add buy milk and call mom tomorrow at 3pm") and the app turns it into
   one or more to-dos, or into a note, via a confirmation sheet.

Data is **local-first**: everything is stored on the device, the app has no
backend, and it works fully offline.

---

## 2. Stack, and why

| Concern | Choice | Rationale |
| --- | --- | --- |
| Framework | Flutter 3.41 (stable), Dart 3.11 | One codebase for Android, iOS and web — the web build is what gets deployed to a public URL. |
| UI | Material 3 | Built in, themeable, no third-party design dependency. |
| State | `ChangeNotifier` + `InheritedNotifier` | The app's state is one small object graph. Riverpod/Bloc would add a dependency and a concept tax without buying anything here. See §4. |
| Persistence | `shared_preferences` (JSON documents) | Works on every Flutter target including web (localStorage) with zero native setup, which matters because the web build is a first-class deliverable. Access is confined to one class so it can be replaced — see §5. |
| Speech | `speech_to_text` | Uses the platform engines (Web Speech API on web, `SFSpeechRecognizer`/`SpeechRecognizer` on iOS/Android). Free, no API key, no audio leaves the device except by the platform engine's own design. |
| NL parsing | Hand-written rules (`voice_parser.dart`) | Runs offline, deterministic, and unit-testable. An LLM parser is a plausible upgrade — see §9. |

**Explicit non-goals for v1:** user accounts, cloud sync, collaboration,
recurring tasks, attachments. Don't add these without being asked.

---

## 3. Repository layout

```
lib/
├── main.dart                    # Entry point: build dependencies, await state, runApp
├── app.dart                     # MaterialApp, themes, root scope wiring
├── core/                        # Cross-cutting helpers, no feature knowledge
│   ├── date_format.dart         # Human date labels ("Today 17:00", "Mon 12 May")
│   ├── id.dart                  # newId()
│   ├── json_utils.dart          # Defensive JSON readers
│   └── theme.dart               # Light/dark ThemeData
├── models/                      # Immutable value types. No Flutter imports.
│   ├── note.dart
│   ├── priority.dart
│   └── todo.dart
├── data/                        # State + persistence
│   ├── app_state.dart           # AppState (ChangeNotifier): the single source of truth
│   ├── app_state_scope.dart     # AppStateScope: InheritedNotifier access
│   └── store.dart               # AppStore interface + SharedPreferences implementation
└── features/                    # One directory per user-facing capability
    ├── home/home_shell.dart     # Scaffold, tabs, shared search, voice FAB
    ├── todos/                   # todo_list_view, todo_tile, todo_editor_sheet
    ├── notes/                   # notes_view, note_editor_page
    └── voice/                   # voice_capture_sheet, voice_parser, speech_service
test/                            # Unit + widget tests, mirroring lib/
tool/                            # bootstrap.sh, deploy_netlify.sh
web/                             # index.html, manifest, and the Netlify _redirects/_headers
```

**Dependency direction is strictly one-way:**

```
features  →  data  →  models
    ↓         ↓
  core  ←  core
```

- `models/` imports only `core/` and Dart. Never Flutter, never `data/`, never `features/`.
- `core/` imports nothing from `models/`, `data/` or `features/`.
- `data/` may import `models/` and `core/`. Never `features/`.
- `features/` may import everything below it.
- No feature imports another feature's widgets. Shared UI goes in `core/` or a
  new widget under `features/` that both can use — or lift state into `AppState`.

---

## 4. State management rules

`AppState` (`lib/data/app_state.dart`) is the **single source of truth** for
todos and notes. It is a `ChangeNotifier` reached through
`AppStateScope.of(context)`.

Rules:

- Widgets **read** through `AppStateScope.of(context)`. `InheritedNotifier`
  subscribes the caller, so the widget rebuilds on change. Do not cache the
  `AppState` in a field of a `StatelessWidget`.
- Widgets **never mutate a list directly**. Every change goes through a method
  on `AppState` (`addTodo`, `toggleTodo`, `upsertNote`, …).
- `Todo` and `Note` are **immutable**. Change them with `copyWith`. Never
  mutate a collection owned by `AppState` (`state.todos` returns an unmodifiable view).
- Local, ephemeral UI state (which tab is open, the current search text, the
  selected filter) belongs in `StatefulWidget` state, **not** in `AppState`.
  If it does not need to survive a restart, it does not belong in `AppState`.
- `AppState` persists automatically after every mutation, debounced by 250 ms.
  Callers never save explicitly.

---

## 5. The persistence boundary

`AppStore` (`lib/data/store.dart`) is the only interface that knows how data is
stored. `SharedPreferencesAppStore` is the current implementation. An
`InMemoryAppStore` lives in the same file for tests.

**If you change the storage engine** (to Drift/SQLite for scale or queries, or
to Supabase/Firebase for sync and multi-device), you implement `AppStore` and
change the one construction site in `main.dart`. Nothing else in the app may
change. Do not leak `SharedPreferences` types outside `store.dart`.

**Serialisation contract:** JSON keys are a public API — a user's device holds
data written by an older build. When you add a field:

1. Give it a default in the model constructor so old records still parse.
2. Read it in `fromJson` through the helpers in `core/json_utils.dart`
   (`readString`, `readDate`, `readBool`). Never a raw `as String` cast — one
   malformed field would otherwise lose the user's whole list.
3. If the key format changes incompatibly, bump the version suffix in the
   preferences key (`voice_todo.todos.v1` → `v2`) and write a migration.

---

## 6. The voice pipeline

This is the most intricate part of the app. It runs in two stages:

```
speech_to_text  →  raw transcript  →  VoiceParser  →  VoiceParseResult  →  confirm sheet  →  AppState
   (SpeechService)                      (pure Dart)      (tasks + note)      (user edits)
```

1. **`SpeechService`** (`features/voice/speech_service.dart`) is the only place
   that touches the `speech_to_text` plugin. It exposes
   `initialize/start/stop` and reports availability. It **must** fail soft:
   if speech is unavailable (Firefox, mic denied, no microphone), it returns
   `false` and the UI offers the typed-input path. Never let a speech failure
   block to-do capture.

   Two traps live here, both already handled — keep them that way:

   - **The plugin's barrel file does not re-export its model classes.**
     `package:speech_to_text/speech_to_text.dart` re-exports only `ListenMode`,
     `SpeechConfigOption` and `SpeechListenOptions`. `SpeechRecognitionError`
     and `SpeechRecognitionResult` must be imported from their own libraries
     (`package:speech_to_text/speech_recognition_error.dart` and
     `.../speech_recognition_result.dart`) or neither callback type resolves.
   - **`errorMsg` is not user-facing text.** The plugin documents it as "not
     meant for display": it is a code like `error_no_match`. Run it through
     `SpeechService.describeError` before showing it to anyone, and keep that
     mapping's test (`test/speech_service_test.dart`) in step with the codes the
     plugin documents when you upgrade it.
2. **`VoiceParser`** (`features/voice/voice_parser.dart`) is **pure Dart with no
   Flutter imports**, so it is directly unit-testable. It converts a transcript
   into a `VoiceParseResult` of `ParsedTask`s and/or a `ParsedNote`.
3. **`VoiceCaptureSheet`** shows the parse result as an **editable** preview
   before anything is written to `AppState`.

### Parser invariants

- The parser is **best-effort, never authoritative**. Because the user confirms
  and edits the result, a wrong guess costs one tap, not bad data. Prefer
  over-splitting to dropping content.
- The parser is **deterministic**: `now` is injected via the `now:` parameter so
  tests do not depend on the wall clock. Never call `DateTime.now()` inside
  parsing logic — take it from the parameter.
- Unrecognised text is **never discarded**. If nothing matches, the whole
  utterance becomes a single task.
- Adding a phrasing? Add a `RegExp` to the relevant list (`_noteLeads`,
  `_taskLeads`, `_highPriority`, `_lowPriority`) or a branch in `_extractDue`,
  then **add a test case in `test/voice_parser_test.dart`**. Untested parser
  changes are not acceptable; this file is the app's riskiest logic.

### Platform permission requirements (do not remove)

- **Android** — `android/app/src/main/AndroidManifest.xml` needs
  `RECORD_AUDIO`, `INTERNET`, and a `<queries>` block for
  `android.speech.RecognitionService`.
- **iOS** — `ios/Runner/Info.plist` needs `NSMicrophoneUsageDescription` and
  `NSSpeechRecognitionUsageDescription`. Both are shown to the user verbatim;
  keep them honest.
- **Web** — the Web Speech API only works on a **secure context** (HTTPS or
  `localhost`). Voice does not work over plain HTTP, and Firefox does not
  implement it at all. The typed-input fallback exists for exactly these cases.

---

## 7. Commands

```bash
# Setup
flutter pub get

# Run
flutter run -d chrome          # web, fastest loop for UI work
flutter run -d <device-id>     # android/ios; see `flutter devices`

# Quality gates — all three must pass before you call work done
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test

# Web release build (output in build/web)
flutter build web --release

# Deploy the web build (see §8)
bash tool/deploy_netlify.sh
```

This project has **no `build_runner` step and no generated code**. Models
serialise by hand. Do not introduce `freezed`, `json_serializable` or
`hive_generator` — the serialisation surface is small and hand-written code
keeps `flutter pub get && flutter run` the entire setup.

---

## 8. Deployment

The web build is served as a static site on **Netlify**. `build/web` is the
deployable artifact:

```
flutter build web --release  →  build/web  →  netlify deploy --prod --dir=build/web
```

`bash tool/deploy_netlify.sh` runs both steps and refuses to deploy if the
Netlify metadata did not make it into the build.

Two files in `web/` are load-bearing and must not be removed. Flutter copies the
contents of `web/` into `build/web/`, and Netlify reads both from the *publish
root* — which is exactly why they live there instead of in `netlify.toml`:

- **`web/_redirects`** — rewrites `/*` to `/index.html` with a 200. Without it,
  every deep link and every refresh 404s. Real files still win over the rule, so
  assets under `/assets/` and `/canvaskit/` are unaffected.

  One rule per line, unwrapped: `/*    /index.html   200`. Unlike
  `netlify.toml`, this file is not whitespace-insensitive, and a rule whose
  destination lands on the next line parses as a rule with *no* destination.
  Netlify then drops it and 404s every deep link **while the deploy reports
  success**. `tool/deploy_netlify.sh` asserts the shape for exactly this reason.
- **`web/_headers`** — `no-cache` on `index.html` and
  `flutter_service_worker.js`. Without it a browser serves a stale entrypoint
  after a deploy and boots against hashed assets that no longer exist.

Do **not** add a long-lived `Cache-Control` to `/main.dart.js` or
`/flutter_bootstrap.js`: those filenames are not content-hashed, so a long TTL
would pin returning users to old code.

`firebase.json` is kept as a working alternative — the same two properties
expressed as a rewrite and a header block — for anyone deploying to Firebase
Hosting instead.

`flutter build web` renders text with CanvasKit/skwasm; the first load downloads
the engine, so expect a slower cold start than a plain HTML page. That is the
price of one codebase, and it is the accepted trade-off here.

---

## 9. Known limitations and the upgrade path

Ordered by what a maintainer would most likely tackle next:

1. **Cloud sync / multi-device.** Implement `AppStore` against a remote backend
   (Supabase and Firebase are the pragmatic choices for Flutter). The interface
   is already async. Requires auth, which requires a `userId` on each model and
   per-user storage keys.
2. **LLM-backed parsing.** The rule-based parser is intentionally offline and
   free. For messier input ("move my dentist thing to next week, I'm swamped"),
   an LLM that returns structured JSON would be materially better. It would
   replace the internals of `VoiceParser.parse` behind the same
   `VoiceParseResult` return type, requires a network call and an API key, and
   must keep the confirm-before-save step.
3. **Storage at scale.** `shared_preferences` rewrites the whole document on
   every save. That is fine for thousands of items and not fine for millions.
   Move to Drift.
4. **Notifications** for due dates, **recurring tasks**, **tags/labels**,
   **note↔todo links**, **undo** on delete.

---

## 10. Working agreements

- **Never `DateTime.now()` in the parser or in persistence** — `VoiceParser.parse`
  takes a `now:` argument precisely so its tests are deterministic. Convenience
  getters that read the wall clock (`Todo.isOverdue`, `Todo.isDueToday`) are
  fine for display, but don't let that dependency spread into logic that needs
  testing. Stored timestamps are local-time ISO-8601 strings.
- **`flutter analyze` must be clean.** Do not add `// ignore:` comments to
  silence real problems.
- **Tests:** every change to `voice_parser.dart`, `store.dart` or `app_state.dart`
  needs test coverage. Widget tests are required for new interactive UI.
- **Accessibility:** icon-only buttons need a `tooltip` or `Semantics` label;
  the mic button needs a state-dependent label ("Start voice capture" /
  "Stop listening"). Tap targets ≥ 48 dp.
- **Comments explain *why*, not *what*.** Match the surrounding density.
- Keep the app compiling on **all** targets. `dart:html` and other
  web-only libraries are banned; use `package:flutter/foundation.dart`'s
  `kIsWeb` for platform branching.
