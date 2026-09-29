import 'package:flutter_test/flutter_test.dart';
import 'package:voice_todo/features/voice/speech_service.dart';

/// The error codes below are the ones `speech_to_text` documents in its
/// [SpeechErrorListener] typedef: Android recognizer codes, the three observed
/// on iOS, and the `error_unknown (...)` catch-all both platforms emit.
const List<String> _documentedCodes = <String>[
  'error_audio_error',
  'error_client',
  'error_permission',
  'error_network',
  'error_network_timeout',
  'error_no_match',
  'error_busy',
  'error_server',
  'error_speech_timeout',
  'error_language_not_supported',
  'error_language_unavailable',
  'error_server_disconnected',
  'error_too_many_requests',
  'error_speech_recognizer_disabled',
  'error_retry',
];

void main() {
  group('SpeechService.describeError', () {
    test('every code the plugin documents produces a message', () {
      for (final String code in _documentedCodes) {
        expect(
          SpeechService.describeError(code),
          isNotEmpty,
          reason: '$code has no message',
        );
      }
    });

    test('no message leaks a raw error_ code to the user', () {
      for (final String code in _documentedCodes) {
        expect(
          SpeechService.describeError(code),
          isNot(contains('error_')),
          reason: '$code is showing the user a plugin code',
        );
      }
    });

    test('messages are sentences, not fragments', () {
      for (final String code in _documentedCodes) {
        final String message = SpeechService.describeError(code);
        expect(message.trim(), equals(message), reason: '$code is untrimmed');
        expect(message, endsWith('.'), reason: '$code is not a sentence');
        expect(
          message[0],
          equals(message[0].toUpperCase()),
          reason: '$code is not capitalised',
        );
      }
    });

    test('retryable network failures share one message', () {
      // The user's action is the same for all of these, so the wording should
      // be too — differing text here would imply a distinction that isn't real.
      final String expected = SpeechService.describeError('error_network');
      for (final String code in <String>[
        'error_server',
        'error_server_disconnected',
        'error_too_many_requests',
      ]) {
        expect(SpeechService.describeError(code), equals(expected));
      }
    });

    test('an unrecognised code degrades to the code itself', () {
      // Better a cryptic string than a swallowed failure.
      expect(
        SpeechService.describeError('error_unknown (7)'),
        equals('error_unknown (7)'),
      );
    });
  });
}
