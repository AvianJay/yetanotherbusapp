import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    if let delegate = NSApp.delegate as? AppDelegate {
      delegate.configureAppLaunchBridge(
        messenger: flutterViewController.engine.binaryMessenger
      )
    }

    super.awakeFromNib()
  }
}
