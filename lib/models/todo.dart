import '../core/date_format.dart';
import '../core/id.dart';
import '../core/json_utils.dart';
import 'priority.dart';

/// A single actionable item.
///
/// Immutable: every change produces a new instance via [copyWith], which is
/// what lets [AppState] diff and persist cheaply and keeps widgets honest
/// about rebuilding.
class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.createdAt,
    this.details = '',
    this.isDone = false,
    this.priority = Priority.normal,
    this.dueAt,
    this.completedAt,
  });

  final String id;
  final String title;
  final String details;
  final bool isDone;
  final Priority priority;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  /// Past its due date and still open. Drives the "Overdue" section.
  bool get isOverdue {
    final DateTime? due = dueAt;
    return !isDone && due != null && due.isBefore(DateTime.now());
  }

  bool get isDueToday {
    final DateTime? due = dueAt;
    return due != null && isSameDay(due, DateTime.now());
  }

  bool get hasDetails => details.trim().isNotEmpty;

  Todo copyWith({
    String? title,
    String? details,
    bool? isDone,
    Priority? priority,
    DateTime? dueAt,
    bool clearDueAt = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return Todo(
      id: id,
      title: title ?? this.title,
      details: details ?? this.details,
      isDone: isDone ?? this.isDone,
      priority: priority ?? this.priority,
      // Explicit clear flags: `null` means "leave alone", so clearing a date
      // needs its own signal rather than an ambiguous null.
      dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      createdAt: createdAt,
    );
  }

  /// Flips completion, stamping or clearing the completion time so the
  /// "completed" ordering stays meaningful.
  Todo toggled() => isDone
      ? copyWith(isDone: false, clearCompletedAt: true)
      : copyWith(isDone: true, completedAt: DateTime.now());

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'details': details,
    'isDone': isDone,
    'priority': priority.name,
    'dueAt': writeDate(dueAt),
    'completedAt': writeDate(completedAt),
    'createdAt': writeDate(createdAt),
  };

  factory Todo.fromJson(Map<String, Object?> json) => Todo(
    id: readString(json['id'], fallback: newId()),
    title: readString(json['title']),
    details: readString(json['details']),
    isDone: readBool(json['isDone']),
    priority: Priority.fromName(json['priority']),
    dueAt: readDate(json['dueAt']),
    completedAt: readDate(json['completedAt']),
    createdAt: readDate(json['createdAt']) ?? DateTime.now(),
  );
}
