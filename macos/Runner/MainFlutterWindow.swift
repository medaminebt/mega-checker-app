import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Sensible default + minimum window size, centered on screen.
    let initialSize = NSSize(width: 1060, height: 720)
    self.setContentSize(initialSize)
    self.contentMinSize = NSSize(width: 820, height: 560)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
