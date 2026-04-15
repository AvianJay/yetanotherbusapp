import ActivityKit
import Flutter
import Foundation

final class LiveActivityBridge {
  static let shared = LiveActivityBridge()

  private let channelName = "tw.avianjay.taiwanbus.flutter/live_activity"
  private var channel: FlutterMethodChannel?
  private var currentActivityId: String?

  private init() {}

  func endAllActivitiesFromHost() {
    guard #available(iOS 16.2, *) else {
      currentActivityId = nil
      return
    }
    endAllActivities()
  }

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
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call: call, result: result)
    }
    channel = methodChannel
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startLiveActivity":
      handleStart(call: call, result: result)
    case "updateLiveActivity":
      handleUpdate(call: call, result: result)
    case "endLiveActivity":
      handleEnd(result: result)
    case "isLiveActivityActive":
      handleIsActive(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Start

  private func handleStart(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 16.2, *) else {
      result(FlutterError(code: "unsupported", message: "Live Activities require iOS 16.2+", details: nil))
      return
    }

    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      result(FlutterError(code: "disabled", message: "Live Activities are disabled.", details: nil))
      return
    }

    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_args", message: "Missing arguments.", details: nil))
      return
    }

    let routeName = args["routeName"] as? String ?? ""
    let pathName = args["pathName"] as? String ?? ""
    let routeKey = args["routeKey"] as? Int ?? 0
    let provider = args["provider"] as? String ?? ""
    let pathId = args["pathId"] as? Int ?? 0
    let displayStopId = args["displayStopId"] as? Int ?? 0
    let displayStopName = args["displayStopName"] as? String ?? ""
    let previousStopName = args["previousStopName"] as? String
    let nextStopName = args["nextStopName"] as? String
    let lineStopNames = args["lineStopNames"] as? [String] ?? []
    let lineCurrentStopIndex = args["lineCurrentStopIndex"] as? Int
    let lineHighlightedStopIndex = args["lineHighlightedStopIndex"] as? Int
    let modeLabel = args["modeLabel"] as? String
    let statusText = args["statusText"] as? String
    let alertKind = args["alertKind"] as? String

    let etaSeconds = args["etaSeconds"] as? Int
    let etaMessage = args["etaMessage"] as? String
    let vehicleId = args["vehicleId"] as? String
    let progressValue = args["progressValue"] as? Int
    let progressTotal = args["progressTotal"] as? Int

    endAllActivities()

    let attributes = BusArrivalAttributes(
      routeName: routeName,
      pathName: pathName,
      routeKey: routeKey,
      provider: provider,
      pathId: pathId
    )

    let state = BusArrivalAttributes.ContentState(
      displayStopId: displayStopId,
      displayStopName: displayStopName,
      previousStopName: previousStopName,
      nextStopName: nextStopName,
      lineStopNames: lineStopNames,
      lineCurrentStopIndex: lineCurrentStopIndex,
      lineHighlightedStopIndex: lineHighlightedStopIndex,
      modeLabel: modeLabel,
      statusText: statusText,
      etaSeconds: etaSeconds,
      etaMessage: etaMessage,
      vehicleId: vehicleId,
      progressValue: progressValue,
      progressTotal: progressTotal,
      updatedAt: Date()
    )

    do {
      let content = ActivityContent(
        state: state,
        staleDate: resolveStaleDate(for: state)
      )
      let activity = try Activity.request(
        attributes: attributes,
        content: content,
        pushType: nil
      )
      currentActivityId = activity.id
      result(activity.id)
    } catch {
      result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: - Update

  private func handleUpdate(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 16.2, *) else {
      result(nil)
      return
    }

    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_args", message: "Missing arguments.", details: nil))
      return
    }

    let displayStopId = args["displayStopId"] as? Int ?? 0
    let displayStopName = args["displayStopName"] as? String ?? ""
    let previousStopName = args["previousStopName"] as? String
    let nextStopName = args["nextStopName"] as? String
    let lineStopNames = args["lineStopNames"] as? [String] ?? []
    let lineCurrentStopIndex = args["lineCurrentStopIndex"] as? Int
    let lineHighlightedStopIndex = args["lineHighlightedStopIndex"] as? Int
    let modeLabel = args["modeLabel"] as? String
    let statusText = args["statusText"] as? String
    let alertKind = args["alertKind"] as? String
    let etaSeconds = args["etaSeconds"] as? Int
    let etaMessage = args["etaMessage"] as? String
    let vehicleId = args["vehicleId"] as? String
    let progressValue = args["progressValue"] as? Int
    let progressTotal = args["progressTotal"] as? Int

    let state = BusArrivalAttributes.ContentState(
      displayStopId: displayStopId,
      displayStopName: displayStopName,
      previousStopName: previousStopName,
      nextStopName: nextStopName,
      lineStopNames: lineStopNames,
      lineCurrentStopIndex: lineCurrentStopIndex,
      lineHighlightedStopIndex: lineHighlightedStopIndex,
      modeLabel: modeLabel,
      statusText: statusText,
      etaSeconds: etaSeconds,
      etaMessage: etaMessage,
      vehicleId: vehicleId,
      progressValue: progressValue,
      progressTotal: progressTotal,
      updatedAt: Date()
    )

    Task {
      guard let activityId = currentActivityId else {
        await MainActor.run { result(nil) }
        return
      }

      let activities = Activity<BusArrivalAttributes>.activities
      guard let activity = activities.first(where: { $0.id == activityId }) else {
        await MainActor.run { result(nil) }
        return
      }

      let content = ActivityContent(
        state: state,
        staleDate: resolveStaleDate(for: state)
      )
      if let alertConfiguration = makeAlertConfiguration(
        kind: alertKind,
        state: state
      ) {
        await activity.update(content, alertConfiguration: alertConfiguration)
      } else {
        await activity.update(content)
      }
      await MainActor.run { result(nil) }
    }
  }

  // MARK: - End

  private func handleEnd(result: @escaping FlutterResult) {
    guard #available(iOS 16.2, *) else {
      result(nil)
      return
    }

    endAllActivities()
    result(nil)
  }

  // MARK: - Is Active

  private func handleIsActive(result: @escaping FlutterResult) {
    guard #available(iOS 16.2, *) else {
      result(false)
      return
    }

    let hasActive = !Activity<BusArrivalAttributes>.activities.filter {
      $0.activityState == .active
    }.isEmpty
    result(hasActive)
  }

  // MARK: - Helpers

  @available(iOS 16.2, *)
  private func endAllActivities() {
    let activities = Activity<BusArrivalAttributes>.activities
    let finalState = BusArrivalAttributes.ContentState(
      displayStopId: 0,
      displayStopName: "",
      previousStopName: nil,
      nextStopName: nil,
      lineStopNames: [],
      lineCurrentStopIndex: nil,
      lineHighlightedStopIndex: nil,
      modeLabel: nil,
      statusText: nil,
      etaSeconds: nil,
      etaMessage: nil,
      vehicleId: nil,
      progressValue: nil,
      progressTotal: nil,
      updatedAt: Date()
    )
    for activity in activities {
      Task {
        let content = ActivityContent(state: finalState, staleDate: nil)
        await activity.end(content, dismissalPolicy: .immediate)
      }
    }
    currentActivityId = nil
  }

  private func resolveStaleDate(
    for state: BusArrivalAttributes.ContentState
  ) -> Date {
    let minimumRefreshWindow: TimeInterval = 120
    guard let etaSeconds = state.etaSeconds, etaSeconds > 0 else {
      return Date().addingTimeInterval(minimumRefreshWindow)
    }

    return Date().addingTimeInterval(
      max(Double(etaSeconds) + 60, minimumRefreshWindow)
    )
  }

  @available(iOS 16.2, *)
  private func makeAlertConfiguration(
    kind: String?,
    state: BusArrivalAttributes.ContentState
  ) -> AlertConfiguration? {
    switch kind {
    case "boarding_imminent":
      return AlertConfiguration(
        title: "快到站了",
        body: "\(state.displayStopName) 即將到站",
        sound: .default
      )
    case "boarded_no_destination":
      return AlertConfiguration(
        title: "已偵測上車",
        body: "要設定下車站嗎？",
        sound: .default
      )
    case "destination_imminent":
      return AlertConfiguration(
        title: "準備下車",
        body: "再幾站就到 \(state.displayStopName)",
        sound: .default
      )
    case "destination_arriving":
      return AlertConfiguration(
        title: "快到站了",
        body: "\(state.displayStopName) 快到了",
        sound: .default
      )
    default:
      return nil
    }
  }
}
