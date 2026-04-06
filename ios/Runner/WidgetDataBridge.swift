import Flutter
import Foundation
import WidgetKit

final class WidgetDataBridge {
  static let shared = WidgetDataBridge()

  private static let appGroupIdentifier = "group.tw.avianjay.taiwanbus.flutter"
  private static let favoriteGroupsKey = "favorite_groups_json"
  private static let favoriteGroupsFileName = "favorite_groups.json"
  private let channelName = "tw.avianjay.taiwanbus.flutter/ios_widgets"
  private var channel: FlutterMethodChannel?

  private init() {}

  func configure(messenger: FlutterBinaryMessenger) {
    if channel != nil {
      return
    }

    let methodChannel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "syncFavoriteGroups":
        guard
          let arguments = call.arguments as? [String: Any],
          let json = arguments["json"] as? String
        else {
          result(
            FlutterError(
              code: "invalid_args",
              message: "Missing favorite group payload.",
              details: nil
            )
          )
          return
        }
        self.syncFavoriteGroupsJSON(json, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = methodChannel
  }

  private func syncFavoriteGroupsJSON(
    _ json: String,
    result: @escaping FlutterResult
  ) {
    guard let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) else {
      result(
        FlutterError(
          code: "app_group_unavailable",
          message: "Unable to open shared app group defaults.",
          details: Self.appGroupIdentifier
        )
      )
      return
    }

    defaults.set(json, forKey: Self.favoriteGroupsKey)
    defaults.set(Date().timeIntervalSince1970, forKey: "favorite_groups_synced_at")
    defaults.synchronize()
    persistFavoriteGroupsJSONToSharedFile(json)

    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }

    result(nil)
  }

  private func persistFavoriteGroupsJSONToSharedFile(_ json: String) {
    guard
      let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
      ),
      let data = json.data(using: .utf8)
    else {
      return
    }

    let fileURL = containerURL.appendingPathComponent(Self.favoriteGroupsFileName)
    do {
      try data.write(to: fileURL, options: .atomic)
    } catch {
      NSLog("WidgetDataBridge failed to persist shared widget payload: %@", error.localizedDescription)
    }
  }
}
