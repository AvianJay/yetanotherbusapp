/// Clock helpers shared by the rail dashboards (TRA today, THSR next).
///
/// Rail times arrive from TDX as bare wall-clock strings in **two** formats:
/// the live board (`/tra/liveboard/...`) emits `HH:MM:SS` while the daily
/// timetable family (`/tra/timetable/od`) emits `HH:MM`. Everything here
/// accepts both, so callers never have to care which endpoint a value came
/// from.
///
/// Times carry no timezone. The device's local clock is used for comparisons,
/// matching what the rest of the app already does (the app ships no `intl` or
/// `timezone` package), which is correct as long as the device is on Taiwan
/// time.
library;

/// Parses a TDX rail clock string against [serviceDate].
///
/// Accepts `HH:MM` and `HH:MM:SS`; returns `null` for empty or malformed
/// input so callers can distinguish "bad data" from "already departed".
///
/// The time is added to [serviceDate]'s midnight as a [Duration] rather than
/// being passed as a `DateTime` hour field. TRA's native JSON feed has not
/// been observed to emit extended-hours notation, but if a `24:15` ever shows
/// up this lands it on the next calendar day instead of rejecting it. Taiwan
/// has no daylight saving, so adding an absolute duration to a local
/// `DateTime` is exact.
DateTime? parseRailClockTime(String value, DateTime serviceDate) {
  final text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  final parts = text.split(':');
  // `>= 2`, never `== 2`: the live board's HH:MM:SS splits into three.
  if (parts.length < 2) {
    return null;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }
  if (hour < 0 || hour > 27 || minute < 0 || minute > 59) {
    return null;
  }
  final midnight = DateTime(serviceDate.year, serviceDate.month, serviceDate.day);
  return midnight.add(Duration(hours: hour, minutes: minute));
}

/// The moment a train is actually expected to leave, delay included.
///
/// Returns `null` when [scheduledDeparture] cannot be parsed. Negative delays
/// are ignored: TDX occasionally reports a train as early, but a train never
/// leaves a station ahead of its published time.
DateTime? resolveRailDeparture({
  required String scheduledDeparture,
  required DateTime serviceDate,
  int delayMinutes = 0,
}) {
  final scheduled = parseRailClockTime(scheduledDeparture, serviceDate);
  if (scheduled == null) {
    return null;
  }
  if (delayMinutes <= 0) {
    return scheduled;
  }
  return scheduled.add(Duration(minutes: delayMinutes));
}

/// Whether a train has already left, so the UI can grey it out.
///
/// Unparsable times return `false` — never grey out a row on data we could not
/// read. A train leaving this very minute is *not* past yet.
bool isRailDeparturePast({
  required String scheduledDeparture,
  required DateTime serviceDate,
  int delayMinutes = 0,
  DateTime? now,
}) {
  final departure = resolveRailDeparture(
    scheduledDeparture: scheduledDeparture,
    serviceDate: serviceDate,
    delayMinutes: delayMinutes,
  );
  if (departure == null) {
    return false;
  }
  return (now ?? DateTime.now()).isAfter(departure);
}

/// Whole minutes until departure, or `null` when unknown or already past.
int? minutesUntilRailDeparture({
  required String scheduledDeparture,
  required DateTime serviceDate,
  int delayMinutes = 0,
  DateTime? now,
}) {
  final departure = resolveRailDeparture(
    scheduledDeparture: scheduledDeparture,
    serviceDate: serviceDate,
    delayMinutes: delayMinutes,
  );
  if (departure == null) {
    return null;
  }
  final remaining = departure.difference(now ?? DateTime.now());
  if (remaining.isNegative) {
    return null;
  }
  return remaining.inMinutes;
}

/// Trip length label such as `1h52m` / `52m`, or `''` when unknown.
///
/// Behaviour is identical to the two private `_duration` copies this replaces
/// (`tra_screen.dart` and `thsr_dashboard_screen.dart`), including returning
/// `''` for a trip that crosses midnight.
String railDurationLabel(String departure, String arrival) {
  final departureMinutes = _minutesOfDay(departure);
  final arrivalMinutes = _minutesOfDay(arrival);
  if (departureMinutes == null || arrivalMinutes == null) {
    return '';
  }
  final diff = arrivalMinutes - departureMinutes;
  if (diff <= 0) {
    return '';
  }
  final hours = diff ~/ 60;
  final minutes = diff % 60;
  if (hours > 0) {
    return '${hours}h${minutes}m';
  }
  return '${minutes}m';
}

int? _minutesOfDay(String value) {
  final parsed = parseRailClockTime(value, DateTime(2000));
  if (parsed == null) {
    return null;
  }
  return parsed.difference(DateTime(2000)).inMinutes;
}
