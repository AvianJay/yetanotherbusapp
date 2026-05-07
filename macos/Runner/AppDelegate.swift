import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let appLaunchChannelName = "tw.avianjay.taiwanbus.flutter/app_launch"
  private var appLaunchChannel: FlutterMethodChannel?
  private var pendingAuthPayload: [String: Any]?
  private var isLaunchListenerReady = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  func configureAppLaunchBridge(messenger: FlutterBinaryMessenger) {
    if appLaunchChannel != nil {
      return
    }
    let channel = FlutterMethodChannel(
      name: appLaunchChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "setLaunchListenerReady":
        self.isLaunchListenerReady = true
        result(nil)
      case "takeInitialLaunchAction":
        result(self.pendingAuthPayload)
        self.pendingAuthPayload = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    appLaunchChannel = channel
  }

  @objc private func handleGetURLEvent(
    _ event: NSAppleEventDescriptor,
    withReplyEvent replyEvent: NSAppleEventDescriptor
  ) {
    guard
      let rawUrl = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
      let url = URL(string: rawUrl),
      let payload = authPayload(for: url)
    else {
      return
    }

    if isLaunchListenerReady, let appLaunchChannel {
      appLaunchChannel.invokeMethod("onLaunchAction", arguments: payload)
    } else {
      pendingAuthPayload = payload
    }
  }

  private func authPayload(for url: URL) -> [String: Any]? {
    guard url.scheme?.lowercased() == "yabus", url.host?.lowercased() == "auth-callback" else {
      return nil
    }
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    var payload: [String: Any] = ["target": "auth_callback"]
    for item in components?.queryItems ?? [] {
      payload[item.name] = item.value ?? ""
    }
    if let fragment = components?.fragment, !fragment.isEmpty {
      var parser = URLComponents()
      parser.percentEncodedQuery = fragment
      for item in parser.queryItems ?? [] {
        payload[item.name] = item.value ?? ""
      }
    }
    if payload["token"] == nil && payload["error"] == nil {
      return nil
    }
    return payload
  }
}
