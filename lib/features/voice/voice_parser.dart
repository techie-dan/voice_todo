import '../../models/priority.dart';

/// One to-do extracted from a spoken sentence.
class ParsedTask {
  const ParsedTask({
    required this.title,
    this.dueAt,
    this.priority = Priority.normal,
  });

  final String title;
  final DateTime? dueAt;
  final Priority priority;

  ParsedTask copyWith({
    String? title,
    DateTime? dueAt,
    bool clearDueAt = false,
    Priority? priority,
  }) => ParsedTask(
    title: title ?? this.title,
    dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
    priority: priority ?? this.priority,
  );
}

/// A note extracted from a spoken sentence.
class ParsedNote {
  const ParsedNote({required this.body});

  final String body;

  /// The opening words, used as the note's title.
  String get title {
    final List<String> words = body.split(' ');
    return words.length <= 6 ? body : '${words.take(6).join(' ')}…';
  }
}

/// The outcome of parsing one utterance.
class VoiceParseResult {
  const VoiceParseResult({this.tasks = const <ParsedTask>[], this.note});

  final List<ParsedTask> tasks;
  final ParsedNote? note;

  bool get isEmpty => tasks.isEmpty && note == null;

  int get itemCount => tasks.length + (note == null ? 0 : 1);
}

/// Turns a spoken utterance into tasks and/or a note.
///
/// Deliberately offline and rule-based. Speech recognition already runs in the
/// platform engine, the web build has to work with no API key, and capture
/// should not depend on a network round trip. This is not a general NLU: it
/// recognises the phrasings people actually use to capture an item, and
/// anything it cannot classify becomes a plain task rather than being dropped.
///
/// Because the capture sheet shows an editable preview before saving, a wrong
/// guess costs the user one tap — so the rules here bias towards
/// over-splitting rather than losing content.
///
/// **[now] is always injected** — never read the wall clock in here. Parse
/// results ("tomorrow at 3pm") are only testable against a fixed clock.
class VoiceParser {
  const VoiceParser();

  // ------------------------------------------------------------- lead phrases

  /// "take a note that ...", "note down ...", "remember that ..." — the
  /// utterance is a note, not a to-do.
  static final List<RegExp> _noteLeads = <RegExp>[
    RegExp(
      r'^\s*(?:(?:ok|okay|hey|hi|so)[,\s]+)?(?:please\s+)?(?:make|take|add|create)\s+a\s+note(?:\s+(?:that|about|saying|to))?[,\s:]*',
      caseSensitive: false,
    ),
    RegExp(
      r'^\s*(?:(?:ok|okay|hey|hi|so)[,\s]+)?(?:please\s+)?note(?:\s+(?:that|down|to|about))?[,\s:]+',
      caseSensitive: false,
    ),
    RegExp(r'^\s*(?:please\s+)?remember\s+that\s+', caseSensitive: false),
    RegExp(
      r'^\s*(?:please\s+)?(?:write|jot)\s+(?:this|that|it)?\s*down[,\s:]*',
      caseSensitive: false,
    ),
  ];

  /// Command frames stripped from the front of a clause. Applied to a fixed
  /// point so "okay please add task to buy milk" unwraps completely.
  static final List<RegExp> _taskLeads = <RegExp>[
    RegExp(r'^\s*(?:ok|okay|hey|hi|so|um|uh|well)[,\s]+', caseSensitive: false),
    RegExp(
      r'^\s*(?:please\s+)?(?:can|could|would)\s+you\s+(?:please\s+)?',
      caseSensitive: false,
    ),
    RegExp(
      r'^\s*(?:please\s+)?i\s+(?:want|need|would\s+like)\s+you\s+to\s+',
      caseSensitive: false,
    ),
    RegExp(
      r'^\s*(?:please\s+)?(?:remind\s+me|reminder)\s*(?:to|that|about)?\s*',
      caseSensitive: false,
    ),
    // An explicit noun frame: "add a task to X", "create a reminder for X".
    RegExp(
      r'^\s*(?:please\s+)?(?:add|create|make|set\s+up|schedule|put|log|start)\s+(?:a|an|the|my)?\s*(?:new\s+)?(?:to[\s-]?dos?|tasks?|reminders?|items?|entries?)\s*(?:to|for|that|about|saying)?[,\s:]*',
      caseSensitive: false,
    ),
    // A bare command verb, but only when it is not introducing an object of
    // its own: "add milk" is a command, "create a report" is the task itself.
    RegExp(
      r'^\s*(?:please\s+)?(?:add|create|make|set\s+up|schedule|put|log|start)\s+(?!(?:a|an|the|my|some|another|it|them|this|that)\b)',
      caseSensitive: false,
    ),
    RegExp(
      r'^\s*(?:please\s+)?(?:to[\s-]?dos?|tasks?|items?|reminders?)\s*(?:to|for|:)?\s*',
      caseSensitive: false,
    ),
    RegExp(
      // Double-quoted because a raw single-quoted string cannot contain one.
      r"^\s*(?:please\s+)?(?:don'?t\s+forget\s+to|remember\s+to|need\s+to|have\s+to|gotta|got\s+to|i\s+should|i\s+must|i\s+need\s+to|i\s+have\s+to|i\s+want\s+to)\s+",
      caseSensitive: false,
    ),
    RegExp(r'^\s*please\s+', caseSensitive: false),
  ];

  // ------------------------------------------------------------------ patterns

  /// Clause boundaries. Splitting on "and" over-splits occasionally ("buy
  /// bread and milk"), which [_isFragment] then repairs.
  static final RegExp _clauseSeparator = RegExp(
    r'\s*(?:[,;]|\band\b|\bthen\b|\balso\b|\bplus\b|\bafter\s+that\b)\s*',
    caseSensitive: false,
  );

  static final RegExp _relative = RegExp(
    r'\bin\s+(a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|\d+)\s+(minutes?|mins?|hours?|hrs?|days?|weeks?|months?)\b',
    caseSensitive: false,
  );

  static final RegExp _dayAfterTomorrow = RegExp(
    r'\b(?:the\s+)?day\s+after\s+tomorrow\b',
    caseSensitive: false,
  );
  static final RegExp _tomorrow = RegExp(r'\btomorrow\b', caseSensitive: false);
  static final RegExp _today = RegExp(r'\btoday\b', caseSensitive: false);
  static final RegExp _tonight = RegExp(
    r'\b(?:tonight|this\s+night)\b',
    caseSensitive: false,
  );
  static final RegExp _nextWeek = RegExp(
    r'\bnext\s+week\b',
    caseSensitive: false,
  );
  static final RegExp _nextMonth = RegExp(
    r'\bnext\s+month\b',
    caseSensitive: false,
  );

  /// Only with a determiner: a bare "morning" is usually part of the task
  /// ("morning routine"), while "this morning" is a time.
  static final RegExp _periodOfDay = RegExp(
    r'\b(?:this\s+|in\s+the\s+)(morning|afternoon|evening|night)\b',
    caseSensitive: false,
  );

  static final RegExp _clockTime = RegExp(
    r'\b(?:at\s+|@\s*)?(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)\b',
    caseSensitive: false,
  );
  static final RegExp _atHour = RegExp(
    r'\bat\s+(\d{1,2})(?::(\d{2}))?\b',
    caseSensitive: false,
  );
  static final RegExp _bareClock = RegExp(r'\b(\d{1,2}):(\d{2})\b');
  static final RegExp _noon = RegExp(
    r'\b(?:at\s+)?(?:noon|midday)\b',
    caseSensitive: false,
  );
  static final RegExp _midnight = RegExp(
    r'\b(?:at\s+)?midnight\b',
    caseSensitive: false,
  );

  static final RegExp _weekday = RegExp(
    r'\b(?:on\s+|next\s+|this\s+|coming\s+)?(monday|tuesday|thursday|wednesday|saturday|sunday|friday|tues|thurs|thur|weds|mon|tue|wed|thu|fri|sat|sun)\b',
    caseSensitive: false,
  );

  static const Map<String, int> _weekdayNumbers = <String, int>{
    'monday': 1,
    'mon': 1,
    'tuesday': 2,
    'tues': 2,
    'tue': 2,
    'wednesday': 3,
    'weds': 3,
    'wed': 3,
    'thursday': 4,
    'thurs': 4,
    'thur': 4,
    'thu': 4,
    'friday': 5,
    'fri': 5,
    'saturday': 6,
    'sat': 6,
    'sunday': 7,
    'sun': 7,
  };

  static const Map<String, int> _wordNumbers = <String, int>{
    'a': 1,
    'an': 1,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
  };

  static final RegExp _highPriority = RegExp(
    r'\b(?:urgent(?:ly)?|asap|a\.s\.a\.p\.?|critical|important|high\s+priority|top\s+priority|must\s+do)\b',
    caseSensitive: false,
  );
  static final RegExp _lowPriority = RegExp(
    r'\b(?:low\s+priority|whenever|someday|some\s+day|no\s+rush|not\s+urgent|eventually)\b',
    caseSensitive: false,
  );

  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _leadingFiller = RegExp(
    r'^(?:on|at|by|due(?:\s+(?:on|by))?|for|to|that|about|the|a|an)\s+',
    caseSensitive: false,
  );
  static final RegExp _trailingFiller = RegExp(
    r'\s+(?:on|at|by|due|for|in|to)$',
    caseSensitive: false,
  );
  static final RegExp _edgePunctuation = RegExp(
    r'^[\s\-–—:,.!?]+|[\s\-–—:,.!?]+$',
  );

  // ---------------------------------------------------------------------- api

  VoiceParseResult parse(String transcript, {DateTime? now}) {
    final String text = transcript.trim();
    if (text.isEmpty) return const VoiceParseResult();
    final DateTime clock = now ?? DateTime.now();

    for (final RegExp lead in _noteLeads) {
      final RegExpMatch? match = lead.firstMatch(text);
      if (match == null) continue;
      final String body = text.substring(match.end).trim();
      if (body.isNotEmpty) {
        return VoiceParseResult(note: ParsedNote(body: _sentenceCase(body)));
      }
    }

    final List<ParsedTask> tasks = <ParsedTask>[];
    for (final String clause in _splitClauses(text)) {
      final ParsedTask? task = _parseClause(clause, clock);
      if (task == null) continue;

      final ParsedTask? previous = tasks.isEmpty ? null : tasks.last;
      if (previous != null && _isFragment(task.title)) {
        // A bare noun after "and" belongs to the previous item: "buy bread and
        // milk" is one errand, not two items.
        tasks[tasks.length - 1] = previous.copyWith(
          title: '${previous.title} and ${task.title}',
          dueAt: task.dueAt ?? previous.dueAt,
        );
        continue;
      }
      tasks.add(task);
    }

    if (tasks.isEmpty) {
      // Nothing was recognised. Never drop what the user said — hand it back as
      // a single editable item.
      final String fallback = _cleanTitle(text);
      if (fallback.length < 2) return const VoiceParseResult();
      return VoiceParseResult(
        tasks: <ParsedTask>[ParsedTask(title: _sentenceCase(fallback))],
      );
    }

    // Capitalisation happens last, once fragments have been merged into whole
    // titles — otherwise a merged fragment keeps the capital it was given
    // ("Buy bread and Milk").
    return VoiceParseResult(
      tasks: <ParsedTask>[
        for (final ParsedTask task in tasks)
          task.copyWith(title: _sentenceCase(task.title)),
      ],
    );
  }

  // ------------------------------------------------------------------ private

  List<String> _splitClauses(String text) => text
      .split(_clauseSeparator)
      .map((String clause) => clause.trim())
      .where((String clause) => clause.isNotEmpty)
      .toList(growable: false);

  ParsedTask? _parseClause(String clause, DateTime now) {
    String working = _stripTaskLeads(clause);

    final ({DateTime? dueAt, String text}) due = _extractDue(working, now);
    working = due.text;

    final ({Priority priority, String text}) priority = _extractPriority(
      working,
    );
    working = priority.text;

    final String title = _cleanTitle(working);
    if (title.length < 2) return null;

    return ParsedTask(
      title: title,
      dueAt: due.dueAt,
      priority: priority.priority,
    );
  }

  String _stripTaskLeads(String clause) {
    String working = clause.trim();
    // Unwrap stacked frames ("okay please add task to ...") to a fixed point.
    for (int pass = 0; pass < 4; pass++) {
      String next = working;
      for (final RegExp lead in _taskLeads) {
        next = next.replaceFirst(lead, '');
      }
      next = next.trim();
      if (next == working) break;
      working = next;
    }
    return working;
  }

  ({Priority priority, String text}) _extractPriority(String text) {
    final RegExpMatch? high = _highPriority.firstMatch(text);
    if (high != null) return (priority: Priority.high, text: _cut(text, high));
    final RegExpMatch? low = _lowPriority.firstMatch(text);
    if (low != null) return (priority: Priority.low, text: _cut(text, low));
    return (priority: Priority.normal, text: text);
  }

  /// Pulls a due date out of [text] and returns the text without it.
  ({DateTime? dueAt, String text}) _extractDue(String text, DateTime now) {
    String working = text;

    // A relative offset fixes both date and time, so it settles the question.
    final RegExpMatch? relative = _relative.firstMatch(working);
    if (relative != null) {
      final int amount = _number(relative.group(1)!) ?? 1;
      final Duration offset = switch (relative.group(2)!.toLowerCase()) {
        'minute' || 'minutes' || 'min' || 'mins' => Duration(minutes: amount),
        'hour' || 'hours' || 'hr' || 'hrs' => Duration(hours: amount),
        'day' || 'days' => Duration(days: amount),
        'week' || 'weeks' => Duration(days: amount * 7),
        _ => Duration(days: amount * 30),
      };
      return (dueAt: now.add(offset), text: _cut(working, relative));
    }

    int? hour;
    int? minute;

    final RegExpMatch? noon = _noon.firstMatch(working);
    final RegExpMatch? midnight = _midnight.firstMatch(working);
    if (noon != null) {
      hour = 12;
      minute = 0;
      working = _cut(working, noon);
    } else if (midnight != null) {
      hour = 0;
      minute = 0;
      working = _cut(working, midnight);
    } else {
      // "3pm" / "15:30 pm" — the explicit form wins.
      final RegExpMatch? meridian = _clockTime.firstMatch(working);
      if (meridian != null) {
        int parsed = int.parse(meridian.group(1)!);
        minute = meridian.group(2) == null ? 0 : int.parse(meridian.group(2)!);
        final bool afternoon = meridian.group(3)!.toLowerCase().startsWith('p');
        if (afternoon && parsed < 12) parsed += 12;
        if (!afternoon && parsed == 12) parsed = 0;
        hour = parsed;
        working = _cut(working, meridian);
      } else {
        // "at 5" / "at 17:30", else a bare "17:30".
        final RegExpMatch? match =
            _atHour.firstMatch(working) ?? _bareClock.firstMatch(working);
        if (match != null) {
          final int parsed = int.parse(match.group(1)!);
          if (parsed <= 23) {
            // Without am/pm, "at 5" means 17:00 far more often than 05:00.
            hour = parsed <= 7 ? parsed + 12 : parsed;
            minute = match.group(2) == null ? 0 : int.parse(match.group(2)!);
            working = _cut(working, match);
          }
        }
      }
    }

    // A named time-of-day needs a determiner to count ("this morning").
    int? periodHour;
    final RegExpMatch? period = _periodOfDay.firstMatch(working);
    if (period != null) {
      periodHour = switch (period.group(1)!.toLowerCase()) {
        'morning' => 9,
        'afternoon' => 14,
        _ => 18,
      };
      working = _cut(working, period);
    }

    DateTime? day;
    if (_dayAfterTomorrow.hasMatch(working)) {
      day = _dateOnly(now).add(const Duration(days: 2));
      working = working.replaceFirst(_dayAfterTomorrow, ' ');
    } else if (_tomorrow.hasMatch(working)) {
      day = _dateOnly(now).add(const Duration(days: 1));
      working = working.replaceFirst(_tomorrow, ' ');
    } else if (_today.hasMatch(working)) {
      day = _dateOnly(now);
      working = working.replaceFirst(_today, ' ');
    } else if (_tonight.hasMatch(working)) {
      day = _dateOnly(now);
      hour ??= 20;
      minute ??= 0;
      working = working.replaceFirst(_tonight, ' ');
    } else if (_nextWeek.hasMatch(working)) {
      day = _dateOnly(now).add(const Duration(days: 7));
      working = working.replaceFirst(_nextWeek, ' ');
    } else if (_nextMonth.hasMatch(working)) {
      day = _dateOnly(now).add(const Duration(days: 30));
      working = working.replaceFirst(_nextMonth, ' ');
    } else {
      final RegExpMatch? weekday = _weekday.firstMatch(working);
      if (weekday != null) {
        final int target = _weekdayNumbers[weekday.group(1)!.toLowerCase()]!;
        int delta = (target - now.weekday) % 7;
        // Naming today's weekday means the next one, not the few hours left.
        if (delta == 0) delta = 7;
        day = _dateOnly(now).add(Duration(days: delta));
        working = _cut(working, weekday);
      }
    }

    if (day == null && hour == null && periodHour == null) {
      return (dueAt: null, text: working);
    }

    if (day == null && hour != null) {
      // A time with no date: today if it is still ahead, otherwise tomorrow.
      final DateTime candidate = DateTime(
        now.year,
        now.month,
        now.day,
        hour,
        minute ?? 0,
      );
      return (
        dueAt: candidate.isAfter(now)
            ? candidate
            : candidate.add(const Duration(days: 1)),
        text: working,
      );
    }

    final DateTime baseDay = day ?? _dateOnly(now);
    final int resolvedHour = hour ?? periodHour ?? 9;
    final DateTime candidate = DateTime(
      baseDay.year,
      baseDay.month,
      baseDay.day,
      resolvedHour,
      minute ?? 0,
    );
    if (candidate.isBefore(now)) {
      // "today" is still today, but the default hour has gone — an item due at
      // 09:00 when it is already 14:00 would otherwise read as overdue.
      return (dueAt: now.add(const Duration(hours: 1)), text: working);
    }
    return (dueAt: candidate, text: working);
  }

  /// Tidies the leftover text into a title. Case is left alone — see [parse].
  String _cleanTitle(String raw) {
    String title = raw.replaceAll(_whitespace, ' ').trim();
    // Time words are removed from the middle of a clause, which can strand a
    // preposition at either end: "call mom on friday at 5pm" → "call mom on".
    for (int pass = 0; pass < 3; pass++) {
      final String before = title;
      title = title.replaceFirst(_leadingFiller, '');
      title = title.replaceFirst(_trailingFiller, '');
      title = title.replaceAll(_edgePunctuation, '').trim();
      if (title == before) break;
    }
    return title;
  }

  /// A single word after "and" is part of the previous item, not a task.
  bool _isFragment(String title) => title.split(' ').length < 2;

  int? _number(String token) =>
      _wordNumbers[token.toLowerCase()] ?? int.tryParse(token);

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// Removes a matched span, leaving a space so neighbouring words do not run
  /// together.
  String _cut(String text, Match match) =>
      text.replaceRange(match.start, match.end, ' ');

  String _sentenceCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}
