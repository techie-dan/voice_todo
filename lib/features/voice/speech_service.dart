// The plugin's barrel file re-exports only ListenMode, SpeechConfigOption and
// SpeechListenOptions. SpeechRecognitionError and SpeechRecognitionResult live
// in their own libraries and must be imported directly, or neither the onError
// nor the onResult callback type resolves.
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Wrapper around the `speech_to_text` plugin.
///
/// This is the only file in the app that imports the plugin. It exists to
/// guarantee one thing: **speech never blocks capture**. Every failure —
/// unsupported browser, denied microphone permission, no microphone, plugin
/// exception — surfaces as `false` from [initialize], and the UI falls back to
/// typing. Nothing here throws.
class SpeechService {
  SpeechService({SpeechToText? engine}) : _engine = engine ?? SpeechToText();

  final SpeechToText _engine;

  bool _initialized = false;
  bool _available = false;
  String? _lastError;

  bool get isAvailable => _available;

  bool get isListening => _engine.isListening;

  /// The most recent failure, for diagnostics. Never surfaced as a hard error:
  /// capture falls back to typing instead.
  String? get lastError => _lastError;

  /// Prepares the engine. Safe to call repeatedly.
  ///
  /// [statusListener] receives engine transitions (`listening`, `done`, …);
  /// [errorListener] receives a human-readable message. Both are advisory.
  Future<bool> initialize({
    required void Function(String status) statusListener,
    required void Function(String message) errorListener,
  }) async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      _available = await _engine.initialize(
        onStatus: statusListener,
        onError: (SpeechRecognitionError error) {
          _lastError = error.errorMsg;
          errorListener(describeError(error.errorMsg));
        },
      );
    } catch (error) {
      // A platform channel that is missing, or a browser without the Web
      // Speech API, lands here.
      _lastError = error.toString();
      _available = false;
    }
    return _available;
  }

  /// Starts listening. [onResult] fires repeatedly with partial transcripts and
  /// once with `isFinal: true`.
  Future<void> start({
    required void Function(String words, bool isFinal) onResult,
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 4),
  }) async {
    try {
      await _engine.listen(
        onResult: (SpeechRecognitionResult result) =>
            onResult(result.recognizedWords, result.finalResult),
        // The plugin's older listenFor/pauseFor/localeId arguments are
        // deprecated in favour of this options object; it is re-exported from
        // the barrel file, so no extra import is needed.
        //
        // cancelOnError ends a session the platform has declared permanently
        // broken (permission revoked mid-session, recognizer disabled), which
        // is what lets the UI fall back to typing instead of spinning forever.
        listenOptions: SpeechListenOptions(
          listenFor: listenFor,
          pauseFor: pauseFor,
          cancelOnError: true,
        ),
      );
    } catch (error) {
      // Swallowed on purpose: the caller keeps whatever transcript it already
      // has and the user can still edit it by hand.
      _lastError = error.toString();
    }
  }

  /// Stops listening, keeping the transcript already produced.
  Future<void> stop() async {
    try {
      await _engine.stop();
    } catch (error) {
      // Nothing useful to do — the transcript is already in the UI.
      _lastError = error.toString();
    }
  }

  Future<void> cancel() async {
    try {
      await _engine.cancel();
    } catch (error) {
      _lastError = error.toString();
    }
  }

  /// Turns a plugin error code into something worth showing a person.
  ///
  /// The plugin documents `errorMsg` as "not meant for display to the user":
  /// it is a code like `error_no_match`, not a sentence. Everything the user
  /// actually needs from it is *whether retrying could help*, so the mapping
  /// is written in those terms. Unknown codes degrade to the raw code, since a
  /// cryptic message still beats a swallowed failure.
  static String describeError(String errorMsg) {
    switch (errorMsg) {
      case 'error_permission':
        return 'Microphone access was denied. Type your items instead.';
      case 'error_no_match':
        return 'Didn\'t catch that. Try again, or type it.';
      case 'error_speech_timeout':
      case 'error_network_timeout':
        return 'Speech timed out. Try again, or type it.';
      case 'error_network':
      case 'error_server':
      case 'error_server_disconnected':
      case 'error_too_many_requests':
        return 'Speech needs a connection that isn\'t available right now.';
      case 'error_busy':
        return 'The speech service is busy. Try again in a moment.';
      case 'error_client':
      case 'error_retry':
        // Android's generic client-side error and iOS's explicit retry hint.
        // Both are transient, and neither tells the user anything actionable
        // beyond "try again" — so they share a message.
        return 'Speech isn\'t available right now. Try again, or type it.';
      case 'error_audio_error':
        return 'The microphone could not be read. Try another input device.';
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        return 'This device has no speech support for your language.';
      case 'error_speech_recognizer_disabled':
        return 'Speech recognition is turned off in system settings.';
      default:
        return errorMsg;
    }
  }
}
