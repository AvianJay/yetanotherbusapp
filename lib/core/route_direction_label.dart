import 'models.dart';

/// One nearby route row together with the direction text that tells it apart
/// from the other direction of the same route at the same stop name.
typedef NearbyRouteRow = ({NearbyStopResult result, String directionLabel});

const _directionPrefix = '往';

/// Placeholders the static sync pipeline writes into `paths.name` when TDX
/// supplied no Destination/Departure/HeadSign for a direction.
const _placeholderPathNames = <String>{'unknown', 'path 0', 'path 1'};

/// Whether [pathName] actually names a destination.
///
/// Mirrors the server's `_should_use_terminal_stop_name`: besides the literal
/// placeholders, some operators publish the route name as the path name, which
/// would render as `往 307` for route 307 — noise that disambiguates nothing.
/// In both cases the caller is better off with the direction ordinal.
bool isMeaningfulPathName(String? pathName, {String? routeName}) {
  final trimmed = pathName?.trim() ?? '';
  if (trimmed.isEmpty) {
    return false;
  }

  final normalized = trimmed.toLowerCase();
  if (_placeholderPathNames.contains(normalized)) {
    return false;
  }

  final normalizedRouteName = routeName?.trim().toLowerCase() ?? '';
  return normalizedRouteName.isEmpty || normalized != normalizedRouteName;
}

/// 去程 / 返程 / 方向 N for a TDX Direction value.
///
/// Returns an empty string for a null [pathId] so callers that have no
/// direction ordinal to offer can opt out of the fallback entirely.
String directionOrdinalLabel(int? pathId) => switch (pathId) {
  null => '',
  0 => '去程',
  1 => '返程',
  _ => '方向 $pathId',
};

/// Human label for one direction of a route, e.g. `往 撫遠街`.
///
/// Falls back to the direction ordinal when the path name is missing or junk.
/// Without that fallback the two directions of one route at one stop name stay
/// visually identical — which is the whole complaint behind this helper.
String routeDirectionLabel({
  required String? pathName,
  int? pathId,
  String? routeName,
}) {
  if (!isMeaningfulPathName(pathName, routeName: routeName)) {
    return directionOrdinalLabel(pathId);
  }

  final trimmed = pathName!.trim();
  return trimmed.startsWith(_directionPrefix)
      ? trimmed
      : '$_directionPrefix $trimmed';
}

/// Labels every route row inside one nearby stop-name group.
///
/// The nearby list groups purely by stop name, so both directions of a route
/// land in the same card. Circular routes routinely publish the *same*
/// destination for both directions, so the path name alone is not always
/// enough — when two rows of the same route would read alike, the direction
/// ordinal is appended: `往 X（去程）` / `往 X（返程）`.
///
/// Input order is preserved; callers should sort before labelling.
List<NearbyRouteRow> labelNearbyRouteDirections(
  List<NearbyStopResult> results,
) {
  final labels = [
    for (final result in results)
      routeDirectionLabel(
        pathName: result.route.description,
        pathId: result.stop.pathId,
        routeName: result.route.routeName,
      ),
  ];

  // Keyed by route name too, so two different routes that happen to share a
  // destination are not mistaken for a collision.
  final counts = <(String, String), int>{};
  for (var index = 0; index < results.length; index++) {
    final key = _collisionKey(results[index], labels[index]);
    counts[key] = (counts[key] ?? 0) + 1;
  }

  return <NearbyRouteRow>[
    for (var index = 0; index < results.length; index++)
      (
        result: results[index],
        directionLabel: _withOrdinalWhenAmbiguous(
          labels[index],
          pathId: results[index].stop.pathId,
          ambiguous:
              (counts[_collisionKey(results[index], labels[index])] ?? 0) > 1,
        ),
      ),
  ];
}

(String, String) _collisionKey(NearbyStopResult result, String label) =>
    (result.route.routeName, label);

String _withOrdinalWhenAmbiguous(
  String label, {
  required int pathId,
  required bool ambiguous,
}) {
  if (!ambiguous) {
    return label;
  }

  final ordinal = directionOrdinalLabel(pathId);
  // `label == ordinal` already happens when the path name was junk and the
  // fallback kicked in — appending would produce `去程（去程）`.
  if (ordinal.isEmpty || label == ordinal) {
    return label;
  }
  if (label.isEmpty) {
    return ordinal;
  }
  return '$label（$ordinal）';
}
