import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let registrar = registrar(forPlugin: "YABusHostBridges") {
      configureBridges(messenger: registrar.messenger())
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    configureBridges(messenger: engineBridge.applicationRegistrar.messenger())
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

  private func configureBridges(messenger: FlutterBinaryMessenger) {
    AppLaunchBridge.shared.configure(messenger: messenger)
    WidgetDataBridge.shared.configure(messenger: messenger)
    LiveActivityBridge.shared.configure(messenger: messenger)
  }
}
