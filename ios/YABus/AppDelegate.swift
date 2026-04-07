import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    AppLaunchBridge.shared.configure(messenger: messenger)
    WidgetDataBridge.shared.configure(messenger: messenger)
    LiveActivityBridge.shared.configure(messenger: messenger)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if AppLaunchBridge.shared.handle(url: url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    LiveActivityBridge.shared.endAllActivitiesFromHost()
    super.applicationWillTerminate(application)
  }
}
