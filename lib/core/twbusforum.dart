import 'package:url_launcher/url_launcher.dart';

Uri buildTwBusForumSearchUri(String vehicleId) {
  return Uri.https(
    'twbusforum.fandom.com',
    '/zhtw/wiki/特殊:搜尋',
    <String, String>{
      'scope': 'internal',
      'navigationSearch': 'true',
      'query': vehicleId.trim(),
    },
  );
}

Future<bool> openTwBusForumSearch(String vehicleId) {
  return launchUrl(
    buildTwBusForumSearchUri(vehicleId),
    mode: LaunchMode.externalApplication,
  );
}
