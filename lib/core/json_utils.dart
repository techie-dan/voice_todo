/// Defensive JSON readers.
///
/// Persisted records outlive the code that wrote them: a device may hold data
/// from an older build, or from a build that crashed mid-write. Reading every
/// field through these helpers means one corrupt entry costs a single record
/// instead of the user's entire list.
library;

DateTime? readDate(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

String readString(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

bool readBool(Object? value, {bool fallback = false}) =>
    value is bool ? value : fallback;

Map<String, Object?> readMap(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : const <String, Object?>{};

/// Encodes a timestamp for storage, or null so absent dates stay absent.
String? writeDate(DateTime? value) => value?.toIso8601String();
