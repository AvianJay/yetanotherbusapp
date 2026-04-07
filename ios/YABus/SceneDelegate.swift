import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if let url = connectionOptions.urlContexts.first?.url {
      _ = AppLaunchBridge.shared.handle(url: url)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    DispatchQueue.main.async { [weak self] in
      self?.configureBridgesIfNeeded()
    }
  }

  override func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
    for urlContext in urlContexts {
      if AppLaunchBridge.shared.handle(url: urlContext.url) {
        return
      }
    }
    super.scene(scene, openURLContexts: urlContexts)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    configureBridgesIfNeeded()
  }

  private func configureBridgesIfNeeded() {
    guard let flutterViewController = window?.rootViewController as? FlutterViewController else {
      return
    }

    let messenger = flutterViewController.binaryMessenger
    AppLaunchBridge.shared.configure(messenger: messenger)
    WidgetDataBridge.shared.configure(messenger: messenger)
    LiveActivityBridge.shared.configure(messenger: messenger)
  }
}
