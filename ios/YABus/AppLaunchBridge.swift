import Flutter
import Foundation

final class AppLaunchBridge {
  static let shared = AppLaunchBridge()
  private let supportedInternalHosts: Set<String> = ["busapp.avianjay.sbs"]
  private let supportedInternalPaths: Set<String> = [
    "/",
    "/search",
    "/favorites",
    "/nearby",
    "/settings",
    "/account",
    "/feedback",
    "/database-settings",
    "/terms-of-service",
    "/privacy-policy",
    "/announcement",
  ]

  private let channelName = "tw.avianjay.taiwanbus.flutter/app_launch"
  private var channel: FlutterMethodChannel?
  private var pendingAction: [String: Any]?
  private var isLaunchListenerReady = false

  private init() {}

  func configure(messenger: FlutterBinaryMessenger) {
    if channel != nil {
      return
    }

    let methodChannel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }

      switch call.method {
      case "setLaunchListenerReady":
        self.isLaunchListenerReady = true
        result(nil)
      case "takeInitialLaunchAction":
        result(self.pendingAction)
        self.pendingAction = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = methodChannel
  }

  @discardableResult
  func handle(url: URL) -> Bool {
    guard let action = payload(for: url) else {
      return false
    }

    if isLaunchListenerReady, let channel {
      channel.invokeMethod("onLaunchAction", arguments: action)
    } else {
      pendingAction = action
    }
    return true
  }

  @discardableResult
  func handle(userActivity: NSUserActivity) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
      let url = userActivity.webpageURL
    else {
      return false
    }
    return handle(url: url)
  }

  private func payload(for url: URL) -> [String: Any]? {
    guard let scheme = url.scheme?.lowercased() else {
      return nil
    }

    if scheme == "yabus" {
      return customSchemePayload(for: url)
    }

    if (scheme == "http" || scheme == "https") && isSupportedInternalHost(url.host) {
      return universalLinkPayload(for: url)
    }

    return nil
  }

  private func customSchemePayload(for url: URL) -> [String: Any]? {
    guard let scheme = url.scheme?.lowercased(), scheme == "yabus" else {
      return nil
    }

    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let host = url.host?.lowercased() ?? ""
    let pathSegments = url.pathComponents.filter { $0 != "/" }

    if host == "favorites" {
      let groupName = queryValue("groupName", from: components) ?? pathSegments.first
      guard let groupName, !groupName.isEmpty else {
        return nil
      }
      return [
        "target": "favorites_group",
        "groupName": groupName,
      ]
    }

    if host == "route" {
      return routePayload(from: components, pathSegments: pathSegments)
    }

    if host == "auth-callback" {
      return authPayload(from: components)
    }

    return nil
  }

  private func universalLinkPayload(for url: URL) -> [String: Any]? {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let pathSegments = url.pathComponents.filter { $0 != "/" }
    let normalizedPath = normalizedLocationPath(for: url)

    if pathSegments.count >= 3 && pathSegments.first == "route" {
      return routePayload(
        provider: pathSegments[1],
        routeKey: Int(pathSegments[2]),
        routeId: queryValue("routeId", from: components),
        pathId: queryInt("pathId", from: components) ?? intValue(at: 3, in: pathSegments),
        stopId: queryInt("stopId", from: components) ?? intValue(at: 4, in: pathSegments),
        destinationPathId: queryInt("destinationPathId", from: components),
        destinationStopId: queryInt("destinationStopId", from: components)
      )
    }

    if pathSegments.count >= 2 && pathSegments.first == "announcement" {
      return internalLocationPayload(from: components, path: normalizedPath)
    }

    if supportedInternalPaths.contains(normalizedPath) {
      return internalLocationPayload(from: components, path: normalizedPath)
    }

    return nil
  }

  private func isSupportedInternalHost(_ rawHost: String?) -> Bool {
    guard let rawHost else {
      return false
    }
    return supportedInternalHosts.contains(rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  }

  private func authPayload(from components: URLComponents?) -> [String: Any]? {
    var payload: [String: Any] = [
      "target": "auth_callback"
    ]
    for key in ["token", "account_id", "device_id", "role", "provider", "display_name", "error"] {
      if let value = queryValue(key, from: components) {
        payload[key] = value
      }
    }
    for item in fragmentItems(from: components) {
      payload[item.name] = item.value ?? ""
    }
    if payload["token"] == nil && payload["error"] == nil {
      return nil
    }
    return payload
  }

  private func routePayload(
    from components: URLComponents?,
    pathSegments: [String]
  ) -> [String: Any]? {
    return routePayload(
      provider: queryValue("provider", from: components) ?? pathSegments.first,
      routeKey: queryInt("routeKey", from: components) ?? intValue(at: 1, in: pathSegments),
      routeId: queryValue("routeId", from: components),
      pathId: queryInt("pathId", from: components) ?? intValue(at: 2, in: pathSegments),
      stopId: queryInt("stopId", from: components) ?? intValue(at: 3, in: pathSegments),
      destinationPathId: queryInt("destinationPathId", from: components),
      destinationStopId: queryInt("destinationStopId", from: components)
    )
  }

  private func routePayload(
    provider: String?,
    routeKey: Int?,
    routeId: String?,
    pathId: Int?,
    stopId: Int?,
    destinationPathId: Int?,
    destinationStopId: Int?
  ) -> [String: Any]? {
    guard let provider, !provider.isEmpty, let routeKey else {
      return nil
    }

    var payload: [String: Any] = [
      "target": "route_detail",
      "provider": provider,
      "routeKey": routeKey,
    ]
    if let routeId, !routeId.isEmpty {
      payload["routeId"] = routeId
    }
    if let pathId {
      payload["pathId"] = pathId
    }
    if let stopId {
      payload["stopId"] = stopId
    }
    if let destinationPathId {
      payload["destinationPathId"] = destinationPathId
    }
    if let destinationStopId {
      payload["destinationStopId"] = destinationStopId
    }
    return payload
  }

  private func internalLocationPayload(
    from components: URLComponents?,
    path: String
  ) -> [String: Any]? {
    guard !path.isEmpty else {
      return nil
    }

    var location = path
    if let query = components?.percentEncodedQuery, !query.isEmpty {
      location += "?\(query)"
    }
    if let fragment = components?.percentEncodedFragment, !fragment.isEmpty {
      location += "#\(fragment)"
    }
    return [
      "target": "internal_location",
      "location": location,
    ]
  }

  private func normalizedLocationPath(for url: URL) -> String {
    let path = url.path.trimmingCharacters(in: .whitespacesAndNewlines)
    if path.isEmpty || path == "/" {
      return "/"
    }
    return path.hasPrefix("/") ? path : "/\(path)"
  }

  private func queryValue(_ name: String, from components: URLComponents?) -> String? {
    components?.queryItems?
      .first(where: { $0.name == name })?
      .value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func fragmentItems(from components: URLComponents?) -> [URLQueryItem] {
    guard let fragment = components?.fragment, !fragment.isEmpty else {
      return []
    }
    var parser = URLComponents()
    parser.percentEncodedQuery = fragment
    return parser.queryItems ?? []
  }

  private func queryInt(_ name: String, from components: URLComponents?) -> Int? {
    guard let value = queryValue(name, from: components) else {
      return nil
    }
    return Int(value)
  }

  private func intValue(at index: Int, in values: [String]) -> Int? {
    guard values.indices.contains(index) else {
      return nil
    }
    return Int(values[index])
  }
}
