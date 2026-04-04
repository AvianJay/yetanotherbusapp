import 'package:geolocator/geolocator.dart';

import 'bus_repository.dart';
import 'models.dart';

class SmartRouteService {
  const SmartRouteService._();

  static RouteUsageProfile? chooseProfileForTime(
    Iterable<RouteUsageProfile> profiles,
    DateTime now,
  ) {
    RouteUsageProfile? bestProfile;
    double bestScore = 0;
    final currentHour = now.hour;
    final previousHour = (currentHour + 23) % 24;
    final nextHour = (currentHour + 1) % 24;

    for (final profile in profiles) {
      final isRelevantNow =
          profile.combinedCountAtHour(currentHour) > 0 ||
          profile.combinedCountAtHour(previousHour) > 0 ||
          profile.combinedCountAtHour(nextHour) > 0;
      if (!isRelevantNow) {
        continue;
      }

      final score = scoreProfileForTime(profile, now);
      if (score > bestScore) {
        bestProfile = profile;
        bestScore = score;
      }
    }
    return bestProfile;
  }

  static double scoreProfileForTime(RouteUsageProfile profile, DateTime now) {
    final currentHour = now.hour;
    final previousHour = (currentHour + 23) % 24;
    final nextHour = (currentHour + 1) % 24;
    final currentOpenCount = profile.countAtHour(currentHour);
    final currentSelectionCount = profile.selectionCountAtHour(currentHour);
    final adjacentOpenCount =
        profile.countAtHour(previousHour) + profile.countAtHour(nextHour);
    final adjacentSelectionCount =
        profile.selectionCountAtHour(previousHour) +
        profile.selectionCountAtHour(nextHour);
    final preferredCount = profile.combinedCountAtHour(profile.preferredHour);
    final recencyDays = profile.latestInteractionAtMs <= 0
        ? 365
        : now
              .difference(
                DateTime.fromMillisecondsSinceEpoch(
                  profile.latestInteractionAtMs,
                ),
              )
              .inDays;
    final recencyBonus = recencyDays <= 2
        ? 1.5
        : recencyDays <= 7
        ? 0.75
        : 0.0;

    return (currentOpenCount * 5) +
        (currentSelectionCount * 3.5) +
        (adjacentOpenCount * 2.5) +
        (adjacentSelectionCount * 1.5) +
        (preferredCount * 0.5) +
        (profile.totalOpens * 0.15) +
        (profile.totalSelections * 0.1) +
        recencyBonus;
  }

  static String buildReason(RouteUsageProfile profile, DateTime now) {
    final currentCount = profile.combinedCountAtHour(now.hour);
    if (currentCount > 0) {
      return '你常在這個時段點開這條路線。';
    }

    final preferredHour = profile.preferredHour;
    final label = preferredHour.toString().padLeft(2, '0');
    return '你通常會在 $label:00 左右點開這條路線。';
  }

  static SmartRouteSuggestion buildSuggestion({
    required RouteUsageProfile profile,
    required double score,
    required String reason,
    required RouteDetailData detail,
    Position? position,
  }) {
    if (position == null) {
      return SmartRouteSuggestion(
        profile: profile,
        score: score,
        reason: reason,
        detail: detail,
      );
    }

    StopInfo? nearestStop;
    PathInfo? nearestPath;
    double? nearestDistance;

    for (final path in detail.paths) {
      final stops = detail.stopsByPath[path.pathId] ?? const <StopInfo>[];
      for (final stop in stops) {
        if (stop.lat == 0 || stop.lon == 0) {
          continue;
        }

        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          stop.lat,
          stop.lon,
        );
        if (nearestDistance == null || distance < nearestDistance) {
          nearestDistance = distance;
          nearestStop = stop;
          nearestPath = path;
        }
      }
    }

    return SmartRouteSuggestion(
      profile: profile,
      score: score,
      reason: reason,
      detail: detail,
      nearestStop: nearestStop,
      nearestPath: nearestPath,
      distanceMeters: nearestDistance,
    );
  }

  static Future<SmartRouteSuggestion?> loadSuggestion({
    required BusRepository repository,
    required Iterable<RouteUsageProfile> profiles,
    required DateTime now,
    Position? position,
  }) async {
    final profile = chooseProfileForTime(profiles, now);
    if (profile == null) {
      return null;
    }
    final score = scoreProfileForTime(profile, now);
    if (score <= 0) {
      return null;
    }

    final detail = await repository.getCompleteBusInfo(
      profile.routeKey,
      provider: profile.provider,
    );
    return buildSuggestion(
      profile: profile,
      score: score,
      reason: buildReason(profile, now),
      detail: detail,
      position: position,
    );
  }
}
