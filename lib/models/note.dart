import '../core/id.dart';
import '../core/json_utils.dart';

/// A free-form note, kept beside the to-do list.
class Note {
  const Note({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.title = '',
    this.body = '',
    this.isPinned = false,
  });

  final String id;
  final String title;
  final String body;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// [body] collapsed to a single line, for list previews.
  String get preview => body.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// A note may be untitled. Fall back to the opening words of the body so
  /// every row in the list has something to show.
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final String summary = preview;
    if (summary.isEmpty) return 'Untitled note';
    return summary.length <= 48 ? summary : '${summary.substring(0, 48)}…';
  }

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  Note copyWith({
    String? title,
    String? body,
    bool? isPinned,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Applies an edit, always advancing [updatedAt].
  Note edited({String? title, String? body}) =>
      copyWith(title: title, body: body, updatedAt: DateTime.now());

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'body': body,
    'isPinned': isPinned,
    'createdAt': writeDate(createdAt),
    'updatedAt': writeDate(updatedAt),
  };

  factory Note.fromJson(Map<String, Object?> json) {
    final DateTime created = readDate(json['createdAt']) ?? DateTime.now();
    return Note(
      id: readString(json['id'], fallback: newId()),
      title: readString(json['title']),
      body: readString(json['body']),
      isPinned: readBool(json['isPinned']),
      createdAt: created,
      updatedAt: readDate(json['updatedAt']) ?? created,
    );
  }
}
