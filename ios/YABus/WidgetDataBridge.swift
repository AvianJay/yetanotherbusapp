import Flutter
import Foundation
import WidgetKit

final class WidgetDataBridge {
  static let shared = WidgetDataBridge()

  private static let fallbackAppGroupIdentifier = "group.tw.avianjay.taiwanbus.flutter"
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
    let syncResult = persistFavoriteGroupsJSON(json)

    guard !syncResult.syncedAppGroupIdentifiers.isEmpty else {
      if #available(iOS 14.0, *) {
        WidgetCenter.shared.reloadAllTimelines()
      }
      NSLog(
        "WidgetDataBridge no usable app group. groupCount=%d, candidates=%@",
        groupCount,
        syncResult.candidateAppGroupIdentifiers.joined(separator: ",")
      )
      result(
        FlutterError(
          code: "app_group_unavailable",
          message: "Unable to open a shared app group container.",
          details: [
            "candidates": syncResult.candidateAppGroupIdentifiers,
            "groupCount": groupCount,
          ]
        )
      )
      return
    }

    NSLog(
      "WidgetDataBridge synced favorite groups. groupCount=%d, syncedGroups=%@, skippedGroups=%@",
      groupCount,
      syncResult.syncedAppGroupIdentifiers.joined(separator: ","),
      syncResult.skippedAppGroupIdentifiers.joined(separator: ",")
    )

    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }

    result(nil)
  }

  private func persistFavoriteGroupsJSON(_ json: String) -> WidgetDataBridgeSyncResult {
    let candidates = WidgetAppGroupResolver.candidateAppGroupIdentifiers(
      fallback: Self.fallbackAppGroupIdentifier
    )
    let data = json.data(using: .utf8)
    var syncedGroups = [String]()
    var skippedGroups = [String]()

    for appGroupIdentifier in candidates {
      guard
        let containerURL = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
      else {
        skippedGroups.append(appGroupIdentifier)
        NSLog(
          "WidgetDataBridge shared container unavailable for %@",
          appGroupIdentifier
        )
        continue
      }

      var didPersist = false
      if let data {
        let fileURL = containerURL.appendingPathComponent(Self.favoriteGroupsFileName)
        do {
          try data.write(to: fileURL, options: .atomic)
          didPersist = true
        } catch {
          NSLog(
            "WidgetDataBridge failed to persist shared widget payload for %@: %@",
            appGroupIdentifier,
            error.localizedDescription
          )
        }
      }

      if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
        defaults.set(json, forKey: Self.favoriteGroupsKey)
        defaults.set(Date().timeIntervalSince1970, forKey: "favorite_groups_synced_at")
        defaults.synchronize()
        didPersist = true
      } else {
        NSLog(
          "WidgetDataBridge app group defaults unavailable for %@",
          appGroupIdentifier
        )
      }

      if didPersist {
        syncedGroups.append(appGroupIdentifier)
      } else {
        skippedGroups.append(appGroupIdentifier)
      }
    }

    return WidgetDataBridgeSyncResult(
      candidateAppGroupIdentifiers: candidates,
      syncedAppGroupIdentifiers: syncedGroups,
      skippedAppGroupIdentifiers: skippedGroups
    )
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

private struct WidgetDataBridgeSyncResult {
  let candidateAppGroupIdentifiers: [String]
  let syncedAppGroupIdentifiers: [String]
  let skippedAppGroupIdentifiers: [String]
}

private enum WidgetAppGroupResolver {
  private static let appGroupsEntitlement = "com.apple.security.application-groups"

  static func candidateAppGroupIdentifiers(fallback: String) -> [String] {
    var identifiers = [String]()
    appendUnique(provisioningProfileAppGroupIdentifiers(), to: &identifiers)
    appendUnique(bundleDerivedAppGroupIdentifiers(), to: &identifiers)
    appendUnique([fallback], to: &identifiers)
    return identifiers
  }

  private static func provisioningProfileAppGroupIdentifiers() -> [String] {
    guard
      let profileURL = Bundle.main.url(
        forResource: "embedded",
        withExtension: "mobileprovision"
      ),
      let profileData = try? Data(contentsOf: profileURL),
      let profileText = String(data: profileData, encoding: .isoLatin1),
      let plistStart = profileText.range(of: "<?xml"),
      let plistEnd = profileText.range(
        of: "</plist>",
        range: plistStart.lowerBound..<profileText.endIndex
      )
    else {
      return []
    }

    let plistText = profileText[plistStart.lowerBound..<plistEnd.upperBound]
    guard
      let plistData = String(plistText).data(using: .utf8),
      let object = try? PropertyListSerialization.propertyList(
        from: plistData,
        options: [],
        format: nil
      ),
      let profile = object as? [String: Any],
      let entitlements = profile["Entitlements"] as? [String: Any],
      let appGroups = entitlements[appGroupsEntitlement] as? [String]
    else {
      return []
    }

    return appGroups
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func bundleDerivedAppGroupIdentifiers() -> [String] {
    guard
      let bundleIdentifier = Bundle.main.bundleIdentifier?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !bundleIdentifier.isEmpty
    else {
      return []
    }

    return ["group.\(bundleIdentifier)"]
  }

  private static func appendUnique(_ values: [String], to identifiers: inout [String]) {
    for value in values {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !identifiers.contains(trimmed) else {
        continue
      }
      identifiers.append(trimmed)
    }
  }
}
