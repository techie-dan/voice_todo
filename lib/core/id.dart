import 'dart:math';

final Random _random = Random.secure();

const String _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// Generates an identifier for a stored record.
///
/// A millisecond timestamp prefix plus eight random base-36 characters. This
/// keeps ids roughly sortable by creation time and makes collisions
/// vanishingly unlikely for the single-user, local-first data this app stores,
/// without taking on a uuid dependency.
String newId() {
  final String stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final String suffix = List<String>.generate(
    8,
    (_) => _alphabet[_random.nextInt(_alphabet.length)],
  ).join();
  return '$stamp-$suffix';
}
