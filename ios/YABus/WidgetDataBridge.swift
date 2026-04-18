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
    channel?.setMethodCallHandler(nil)

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
    let groupCount = favoriteGroupCount(from: json)
    let didPersistSharedFile = persistFavoriteGroupsJSONToSharedFile(json)

    guard let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) else {
      if #available(iOS 14.0, *) {
        WidgetCenter.shared.reloadAllTimelines()
      }
      NSLog(
        "WidgetDataBridge app group defaults unavailable for %@. groupCount=%d, fallbackFileWritten=%@",
        Self.appGroupIdentifier,
        groupCount,
        didPersistSharedFile ? "true" : "false"
      )
      result(
        FlutterError(
          code: "app_group_unavailable",
          message: "Unable to open shared app group defaults. Shared file fallback attempted.",
          details: Self.appGroupIdentifier
        )
      )
      return
    }

    defaults.set(json, forKey: Self.favoriteGroupsKey)
    defaults.set(Date().timeIntervalSince1970, forKey: "favorite_groups_synced_at")
    defaults.synchronize()
    NSLog(
      "WidgetDataBridge synced favorite groups. groupCount=%d, fallbackFileWritten=%@",
      groupCount,
      didPersistSharedFile ? "true" : "false"
    )

    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }

    result(nil)
  }

  private func persistFavoriteGroupsJSONToSharedFile(_ json: String) -> Bool {
    guard
      let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
      ),
      let data = json.data(using: .utf8)
    else {
      NSLog(
        "WidgetDataBridge failed to open shared container for %@",
        Self.appGroupIdentifier
      )
      return false
    }

    let fileURL = containerURL.appendingPathComponent(Self.favoriteGroupsFileName)
    do {
      try data.write(to: fileURL, options: .atomic)
      return true
    } catch {
      NSLog("WidgetDataBridge failed to persist shared widget payload: %@", error.localizedDescription)
      return false
    }
  }

  private func favoriteGroupCount(from json: String) -> Int {
    guard
      let data = json.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let payload = object as? [String: Any]
    else {
      return 0
    }

    return payload.count
  }
}
