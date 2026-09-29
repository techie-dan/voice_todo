# Voice To-Do

A voice-first to-do list and notes app built with Flutter. One codebase for
Android, iOS and the web.

Say *"add buy milk and call mom tomorrow at 3pm"* and get two to-dos, one of
them scheduled. Say *"take a note: the wifi password is hunter2"* and get a
note. Everything is stored on the device and works offline.

---

## Features

**To-dos**
- Create, edit, complete, delete (with undo), and swipe to dismiss.
- Optional due date and time, three priority levels.
- Automatic sectioning into Overdue / Today / Upcoming / No due date / Completed.
- Filters (All, Today, Upcoming, Done), full-text search, and "clear done".

**Notes**
- Free-form notes with optional titles, pin-to-top, and relative timestamps.
- Notes save as you type; an abandoned empty note is discarded rather than kept.

**Voice capture** — the headline feature
- Speak a sentence; the app splits it into items and pulls out dates,
  times, and priorities.
- A confirmation sheet shows every parsed item, individually editable and
  de-selectable, before anything is written to storage.
- Works by typing too, through the same parser — so capture still works on
  browsers that don't implement the Web Speech API.

### Things you can say

| You say | You get |
| --- | --- |
| "add buy milk and call mom" | Two to-dos |
| "buy bread and milk" | One to-do — "milk" alone is treated as part of the previous item |
| "remind me to call the dentist tomorrow at 3pm" | One to-do, due tomorrow 15:00 |
| "submit the report next friday" | One to-do, due Friday 09:00 |
| "call mom in 2 hours" | One to-do, due two hours from now |
| "add urgent fix the login bug" | One high-priority to-do |
| "buy stamps someday" | One low-priority to-do |
| "take out the bins tonight" | One to-do, due today 20:00 |
| "take a note: the wifi password is hunter2" | A note, no to-do |

`AGENTS.md` §6 documents the parser's rules and how to extend them.

---

## Getting started

```bash
flutter pub get

flutter run -d chrome        # web — the fastest loop for UI work
flutter devices              # then: flutter run -d <device-id>
```

Requires Flutter 3.41+ (Dart 3.11+). There is no code-generation step: models
serialise by hand, so `pub get` and `run` is the entire setup.

## Quality gates

```bash
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test
```

## Building and deploying the web app

```bash
flutter build web --release        # output in build/web
bash tool/deploy_netlify.sh        # build + publish to Netlify production
```

The first deploy needs one interactive login:

```bash
npx netlify-cli login
npx netlify-cli sites:create       # or let the deploy prompt you
```

`netlify.toml` points at `build/web`. The SPA rewrite and cache rules live in
`web/_redirects` and `web/_headers` rather than in `netlify.toml`, because
Flutter copies the contents of `web/` into the build output and Netlify applies
those two files from the publish root:

- `web/_redirects` rewrites `/*` to `/index.html`, so deep links and refreshes
  resolve instead of 404ing (real files still take precedence, so assets are
  unaffected);
- `web/_headers` sets `no-cache` on `index.html` and the service worker, so a
  deploy is never masked by a stale entrypoint pointing at hashed assets that no
  longer exist.

`firebase.json` is included as a working alternative if you would rather deploy
to Firebase Hosting — it expresses the same two properties.

Note that a Flutter web build renders with CanvasKit and downloads the engine on
first load, so the cold start is heavier than a plain HTML page. That is the
trade-off for shipping one codebase to three platforms.

---

## Architecture

```
lib/
├── main.dart          entry point: build the store, load state, run the app
├── app.dart           MaterialApp + AppStateScope
├── core/              ids, defensive JSON readers, date labels, theme
├── models/            immutable Todo, Note, Priority — no Flutter imports
├── data/              AppState (single source of truth) + AppStore (persistence)
└── features/          home · todos · notes · voice
```

- **State** is a `ChangeNotifier` (`AppState`) published through an
  `InheritedNotifier` (`AppStateScope`). No state-management package — the
  object graph is small enough that one would only add concepts and risk.
- **Persistence** sits behind the `AppStore` interface. The current
  implementation is `shared_preferences` holding two JSON documents, which is
  the only store that behaves identically on Android, iOS *and* the web with no
  native setup. Swapping in Drift (SQLite) for scale, or Supabase for
  multi-device sync, means implementing that one interface and changing one
  line in `main.dart`.
- **Voice** is two stages: `SpeechService` wraps the platform engine and fails
  soft, then `VoiceParser` — pure Dart, no Flutter — turns a transcript into
  structured items. The parser takes an injected `now`, which is what makes its
  tests deterministic.

`AGENTS.md` is the full contract: dependency direction, state rules, the
serialisation compatibility promise, and the voice pipeline's invariants. Read
it before making non-trivial changes.

## Testing

```
test/voice_parser_test.dart   the parser's rules, against a fixed clock
test/app_state_test.dart      ordering, filtering, mutation, persistence
test/store_test.dart          JSON round-trips and corrupt-record resilience
test/widget_test.dart         shell, editor sheet, and the capture flow
```

## Platform permissions

Speech needs permissions that must stay in the platform config:

- **Android** — `RECORD_AUDIO`, `INTERNET`, and a `<queries>` entry for
  `android.speech.RecognitionService` in `android/app/src/main/AndroidManifest.xml`.
- **iOS** — `NSMicrophoneUsageDescription` and
  `NSSpeechRecognitionUsageDescription` in `ios/Runner/Info.plist`. Both strings
  are shown to the user verbatim.
- **Web** — the Web Speech API requires a secure context (HTTPS or
  `localhost`). Over plain HTTP, or in Firefox, voice is unavailable and the
  app falls back to typed capture.

## Known limitations

- No accounts or cloud sync — data is per-device.
- The parser is rule-based, not an LLM. It handles common capture phrasings and
  falls back to a single editable item for anything else.
- No notifications, recurring tasks, or tags yet.
