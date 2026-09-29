/// How much an item matters, used for sorting and for the chip on each row.
enum Priority {
  low('Low'),
  normal('Normal'),
  high('High');

  const Priority(this.label);

  final String label;

  /// Reads a stored priority name, falling back to [normal] for anything
  /// unrecognised so an old or hand-edited record still loads.
  static Priority fromName(Object? name) => Priority.values.firstWhere(
    (Priority priority) => priority.name == name,
    orElse: () => Priority.normal,
  );
}
