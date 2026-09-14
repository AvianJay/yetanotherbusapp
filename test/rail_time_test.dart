import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/rail_time.dart';

void main() {
  final serviceDate = DateTime(2026, 9, 14);

  group('parseRailClockTime', () {
    test('accepts the HH:MM form used by the OD timetable', () {
      expect(
        parseRailClockTime('18:05', serviceDate),
        DateTime(2026, 9, 14, 18, 5),
      );
    });

    test('accepts the HH:MM:SS form used by the live board', () {
      // The live board and the timetable disagree on format; a `parts.length ==
      // 2` check here would silently reject every live-board value.
      expect(
        parseRailClockTime('18:05:00', serviceDate),
        DateTime(2026, 9, 14, 18, 5),
      );
    });

    test('rolls an extended-hours time onto the next day', () {
      expect(
        parseRailClockTime('24:15', serviceDate),
        DateTime(2026, 9, 15, 0, 15),
      );
    });

    test('returns null for empty and malformed input', () {
      expect(parseRailClockTime('', serviceDate), isNull);
      expect(parseRailClockTime('   ', serviceDate), isNull);
      expect(parseRailClockTime('1805', serviceDate), isNull);
      expect(parseRailClockTime('ab:cd', serviceDate), isNull);
      expect(parseRailClockTime('18:99', serviceDate), isNull);
      expect(parseRailClockTime('99:00', serviceDate), isNull);
    });
  });

  group('isRailDeparturePast', () {
    test('is true once the scheduled time has gone by', () {
      expect(
        isRailDeparturePast(
          scheduledDeparture: '18:05',
          serviceDate: serviceDate,
          now: DateTime(2026, 9, 14, 18, 10),
        ),
        isTrue,
      );
    });

    test('a train leaving this very minute is not past yet', () {
      expect(
        isRailDeparturePast(
          scheduledDeparture: '18:05',
          serviceDate: serviceDate,
          now: DateTime(2026, 9, 14, 18, 5),
        ),
        isFalse,
      );
    });

    test('a delay pushes the boundary out, keeping the train catchable', () {
      // The whole point of the feature: 18:05 + 晚8分 has not left at 18:10.
      expect(
        isRailDeparturePast(
          scheduledDeparture: '18:05',
          serviceDate: serviceDate,
          delayMinutes: 8,
          now: DateTime(2026, 9, 14, 18, 10),
        ),
        isFalse,
      );
      expect(
        isRailDeparturePast(
          scheduledDeparture: '18:05',
          serviceDate: serviceDate,
          delayMinutes: 8,
          now: DateTime(2026, 9, 14, 18, 14),
        ),
        isTrue,
      );
    });

    test('a negative delay never makes a train leave early', () {
      expect(
        isRailDeparturePast(
          scheduledDeparture: '18:05',
          serviceDate: serviceDate,
          delayMinutes: -10,
          now: DateTime(2026, 9, 14, 18, 0),
        ),
        isFalse,
      );
    });

    test('nothing on a future service date is ever past', () {
      expect(
        isRailDeparturePast(
          scheduledDeparture: '06:00',
          serviceDate: DateTime(2026, 9, 15),
          now: DateTime(2026, 9, 14, 23, 50),
        ),
        isFalse,
      );
    });

    test('everything on a past service date is past', () {
      expect(
        isRailDeparturePast(
          scheduledDeparture: '23:50',
          serviceDate: DateTime(2026, 9, 13),
          now: DateTime(2026, 9, 14, 0, 10),
        ),
        isTrue,
      );
    });

    test('an after-midnight train is not past when seen the evening before',
        () {
      // 00:30 on the 15th, looked at 23:50 on the 14th.
      expect(
        isRailDeparturePast(
          scheduledDeparture: '00:30',
          serviceDate: DateTime(2026, 9, 15),
          now: DateTime(2026, 9, 14, 23, 50),
        ),
        isFalse,
      );
    });

    test('unreadable times are never greyed out', () {
      expect(
        isRailDeparturePast(
          scheduledDeparture: '',
          serviceDate: serviceDate,
          now: DateTime(2026, 9, 14, 23, 59),
        ),
        isFalse,
      );
      expect(
        isRailDeparturePast(
          scheduledDeparture: 'nonsense',
          serviceDate: serviceDate,
          now: DateTime(2026, 9, 14, 23, 59),
        ),
        isFalse,
      );
    });
  });

  group('minutesUntilRailDeparture', () {
    test('counts down whole minutes', () {
      expect(
        minutesUntilRailDeparture(
          scheduledDeparture: '18:05',
          serviceDate: serviceDate,
          now: DateTime(2026, 9, 14, 17, 53),
        ),
        12,
      );
    });

    test('is null once the train has gone', () {
      expect(
        minutesUntilRailDeparture(
          scheduledDeparture: '18:05',
          serviceDate: serviceDate,
          now: DateTime(2026, 9, 14, 18, 6),
        ),
        isNull,
      );
    });

    test('is null when the time cannot be read', () {
      expect(
        minutesUntilRailDeparture(
          scheduledDeparture: '',
          serviceDate: serviceDate,
          now: DateTime(2026, 9, 14, 10, 0),
        ),
        isNull,
      );
    });
  });

  group('railDurationLabel', () {
    // Output must stay byte-identical to the two private _duration copies this
    // replaces, so adopting it in THSR later is a pure deletion.
    test('formats hours and minutes', () {
      expect(railDurationLabel('18:10', '20:02'), '1h52m');
    });

    test('formats a sub-hour trip', () {
      expect(railDurationLabel('18:10', '18:52'), '42m');
    });

    test('returns empty for unknown, zero, or midnight-crossing trips', () {
      expect(railDurationLabel('', '20:02'), '');
      expect(railDurationLabel('18:10', ''), '');
      expect(railDurationLabel('18:10', '18:10'), '');
      expect(railDurationLabel('23:30', '00:45'), '');
    });

    test('accepts the live board HH:MM:SS form too', () {
      expect(railDurationLabel('18:10:00', '20:02:00'), '1h52m');
    });
  });
}
