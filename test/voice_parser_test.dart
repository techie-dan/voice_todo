import 'package:flutter_test/flutter_test.dart';
import 'package:voice_todo/features/voice/voice_parser.dart';
import 'package:voice_todo/models/priority.dart';

void main() {
  // Wednesday 14 May 2025, 10:00. Every expectation below is exact because the
  // clock is injected rather than read.
  final DateTime now = DateTime(2025, 5, 14, 10, 0);
  const VoiceParser parser = VoiceParser();

  VoiceParseResult parse(String input) => parser.parse(input, now: now);

  List<String> titles(String input) =>
      parse(input).tasks.map((ParsedTask task) => task.title).toList();

  group('splitting', () {
    test('splits a spoken list at "and"', () {
      expect(titles('Add buy milk and call mom'), <String>[
        'Buy milk',
        'Call mom',
      ]);
    });

    test('keeps a bare noun with the previous item', () {
      // "buy bread and milk" is one errand, not two items.
      expect(titles('Buy bread and milk'), <String>['Buy bread and milk']);
    });

    test('splits on commas', () {
      expect(titles('add pay rent, book flights'), <String>[
        'Pay rent',
        'Book flights',
      ]);
    });

    test('unwraps stacked command frames', () {
      expect(titles('Okay please add task to buy milk'), <String>['Buy milk']);
    });

    test('leaves a verb alone when it introduces its own object', () {
      // "create a report" is the task; "create" is not a command frame here.
      expect(titles('create a report for the meeting'), <String>[
        'Create a report for the meeting',
      ]);
    });

    test('never drops an unrecognised utterance', () {
      expect(titles('sort out the garage thing'), <String>[
        'Sort out the garage thing',
      ]);
    });
  });

  group('due dates', () {
    test('time only, still ahead today', () {
      final ParsedTask task = parse('call mom at 5').tasks.single;
      expect(task.title, 'Call mom');
      expect(task.dueAt, DateTime(2025, 5, 14, 17, 0)); // "at 5" reads as 17:00
    });

    test('time only, already passed, rolls to tomorrow', () {
      expect(
        parse('call mom at 8am').tasks.single.dueAt,
        DateTime(2025, 5, 15, 8, 0),
      );
    });

    test('tomorrow with an explicit time', () {
      final ParsedTask task = parse(
        'Remind me to call the dentist tomorrow at 3pm',
      ).tasks.single;
      expect(task.title, 'Call the dentist');
      expect(task.dueAt, DateTime(2025, 5, 15, 15, 0));
    });

    test('a bare day defaults to 09:00', () {
      expect(
        parse('submit the report tomorrow').tasks.single.dueAt,
        DateTime(2025, 5, 15, 9, 0),
      );
    });

    test('weekday names resolve to the next occurrence', () {
      final ParsedTask task = parse(
        'submit the report next friday',
      ).tasks.single;
      expect(task.title, 'Submit the report');
      expect(task.dueAt, DateTime(2025, 5, 16, 9, 0));
    });

    test("naming today's weekday means next week", () {
      expect(
        parse('standup on wednesday').tasks.single.dueAt,
        DateTime(2025, 5, 21, 9, 0),
      );
    });

    test('relative offsets', () {
      expect(
        parse('call mom in 2 hours').tasks.single.dueAt,
        DateTime(2025, 5, 14, 12, 0),
      );
      expect(
        parse('stretch in 15 minutes').tasks.single.dueAt,
        DateTime(2025, 5, 14, 10, 15),
      );
      expect(
        parse('renew the domain in 3 days').tasks.single.dueAt,
        DateTime(2025, 5, 17, 10, 0),
      );
    });

    test('tonight means 20:00 today', () {
      expect(
        parse('take out the bins tonight').tasks.single.dueAt,
        DateTime(2025, 5, 14, 20, 0),
      );
    });

    test('noon and midnight', () {
      expect(
        parse('lunch with sam at noon').tasks.single.dueAt,
        DateTime(2025, 5, 14, 12, 0),
      );
      expect(
        parse('deploy at midnight').tasks.single.dueAt,
        DateTime(2025, 5, 15, 0, 0),
      );
    });

    test('"today" whose default hour has passed moves forward', () {
      // 09:00 today is already gone; the item should not read as overdue.
      expect(
        parse('call mom today').tasks.single.dueAt,
        DateTime(2025, 5, 14, 11, 0),
      );
    });

    test('no time information leaves the due date empty', () {
      expect(parse('buy stamps').tasks.single.dueAt, isNull);
    });

    test('the time phrase is stripped from the title', () {
      expect(
        parse('call the dentist tomorrow at 3pm').tasks.single.title,
        'Call the dentist',
      );
      expect(parse('call mom on friday').tasks.single.title, 'Call mom');
    });
  });

  group('priority', () {
    test('urgency words set high priority and leave the title', () {
      final ParsedTask task = parse(
        'Add urgent fix the login bug',
      ).tasks.single;
      expect(task.priority, Priority.high);
      expect(task.title, 'Fix the login bug');
    });

    test('deferral words set low priority', () {
      final ParsedTask task = parse('buy stamps someday').tasks.single;
      expect(task.priority, Priority.low);
      expect(task.title, 'Buy stamps');
    });

    test('defaults to normal', () {
      expect(parse('buy stamps').tasks.single.priority, Priority.normal);
    });
  });

  group('notes', () {
    test('"take a note" produces a note, not a task', () {
      final VoiceParseResult result = parse(
        'Take a note: the wifi password is hunter2',
      );
      expect(result.tasks, isEmpty);
      expect(result.note?.body, 'The wifi password is hunter2');
    });

    test('"note that" produces a note', () {
      expect(parse('note that the meeting moved to 3pm').note, isNotNull);
    });

    test('a note title is drawn from the opening words', () {
      final ParsedNote note = parse(
        'take a note: milk eggs bread cheese butter jam and honey',
      ).note!;
      expect(note.body, 'Milk eggs bread cheese butter jam and honey');
      expect(note.title, 'Milk eggs bread cheese butter jam…');
    });

    test('a note title is only truncated when words were actually cut', () {
      // Exactly at the limit. An ellipsis here would claim content was dropped
      // when none was, which is the more misleading of the two errors.
      expect(
        parse('take a note: one two three four five six').note!.title,
        'One two three four five six',
      );
      // One word past it: now the ellipsis is honest.
      expect(
        parse('take a note: one two three four five six seven').note!.title,
        'One two three four five six…',
      );
    });

    test('"take out the bins" is a task, not a note', () {
      expect(
        parse('take out the bins').tasks.single.title,
        'Take out the bins',
      );
    });
  });

  group('result shape', () {
    test('blank input yields nothing', () {
      expect(parse('   ').isEmpty, isTrue);
    });

    test('itemCount counts tasks and the note', () {
      expect(parse('buy milk and call mom').itemCount, 2);
      expect(parse('take a note: hello').itemCount, 1);
      expect(parse('').itemCount, 0);
    });
  });
}
