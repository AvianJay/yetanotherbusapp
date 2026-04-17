import Flutter
import Foundation

final class AppLaunchBridge {
  static let shared = AppLaunchBridge()

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

  private func payload(for url: URL) -> [String: Any]? {
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

    return nil
  }

  private func routePayload(
    from components: URLComponents?,
    pathSegments: [String]
  ) -> [String: Any]? {
    let provider = queryValue("provider", from: components) ?? pathSegments.first
    let routeKey = queryInt("routeKey", from: components) ?? intValue(at: 1, in: pathSegments)
    let pathId = queryInt("pathId", from: components) ?? intValue(at: 2, in: pathSegments)
    let stopId = queryInt("stopId", from: components) ?? intValue(at: 3, in: pathSegments)
    let destinationPathId = queryInt("destinationPathId", from: components)
    let destinationStopId = queryInt("destinationStopId", from: components)

    guard let provider, !provider.isEmpty, let routeKey else {
      return nil
    }

    var payload: [String: Any] = [
      "target": "route_detail",
      "provider": provider,
      "routeKey": routeKey,
    ]
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

  private func queryValue(_ name: String, from components: URLComponents?) -> String? {
    components?.queryItems?
      .first(where: { $0.name == name })?
      .value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
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
