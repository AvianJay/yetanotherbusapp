import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let appLaunchChannelName = "tw.avianjay.taiwanbus.flutter/app_launch"
  private var appLaunchChannel: FlutterMethodChannel?
  private var pendingAuthPayload: [String: Any]?
  private var isLaunchListenerReady = false
  private var hasInstalledUrlHandlers = false

  override init() {
    super.init()
    installUrlHandlersIfNeeded()
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    installUrlHandlersIfNeeded()
    super.applicationWillFinishLaunching(notification)
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    let remainingUrls = urls.filter { !handleIncomingURL($0) }
    if !remainingUrls.isEmpty {
      super.application(application, open: remainingUrls)
    }
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

  private func installUrlHandlersIfNeeded() {
    if hasInstalledUrlHandlers {
      return
    }
    hasInstalledUrlHandlers = true
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
  }

  @objc private func handleGetURLEvent(
    _ event: NSAppleEventDescriptor,
    withReplyEvent replyEvent: NSAppleEventDescriptor
  ) {
    guard
      let rawUrl = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
      let url = URL(string: rawUrl)
    else {
      return
    }

    _ = handleIncomingURL(url)
  }

  @discardableResult
  private func handleIncomingURL(_ url: URL) -> Bool {
    guard let payload = authPayload(for: url) else {
      return false
    }

    if isLaunchListenerReady, let appLaunchChannel {
      appLaunchChannel.invokeMethod("onLaunchAction", arguments: payload)
    } else {
      pendingAuthPayload = payload
    }
    activateAppForIncomingURL()
    return true
  }

  private func activateAppForIncomingURL() {
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      if let window = self.mainFlutterWindow ?? NSApp.windows.first {
        window.makeKeyAndOrderFront(nil)
      }
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
