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

  override func sceneDidDisconnect(_ scene: UIScene) {
    LiveActivityBridge.shared.endAllActivitiesFromHost()
    super.sceneDidDisconnect(scene)
  }

  private func configureBridgesIfNeeded() {
    guard
      let flutterViewController = resolveFlutterViewController(
        from: window?.rootViewController
      )
    else {
      return
    }

    configureBridges(messenger: flutterViewController.binaryMessenger)
  }

  private func configureBridges(messenger: FlutterBinaryMessenger) {
    AppLaunchBridge.shared.configure(messenger: messenger)
    WidgetDataBridge.shared.configure(messenger: messenger)
    LiveActivityBridge.shared.configure(messenger: messenger)
  }

  private func resolveFlutterViewController(
    from viewController: UIViewController?
  ) -> FlutterViewController? {
    guard let viewController else {
      return nil
    }

    if let flutterViewController = viewController as? FlutterViewController {
      return flutterViewController
    }

    if let navigationController = viewController as? UINavigationController {
      for child in navigationController.viewControllers {
        if let match = resolveFlutterViewController(from: child) {
          return match
        }
      }
    }

    if let tabBarController = viewController as? UITabBarController {
      for child in tabBarController.viewControllers ?? [] {
        if let match = resolveFlutterViewController(from: child) {
          return match
        }
      }
    }

    if let presented = viewController.presentedViewController,
      let match = resolveFlutterViewController(from: presented)
    {
      return match
    }

    for child in viewController.children {
      if let match = resolveFlutterViewController(from: child) {
        return match
      }
    }

    return nil
  }
}
