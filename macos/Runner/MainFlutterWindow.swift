import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Pass the command line to Dart's main(args): the scheduled check starts
    // the app with --scheduled-check (see lib/schedule.dart).
    let project = FlutterDartProject()
    project.dartEntrypointArguments = Array(CommandLine.arguments.dropFirst())
    let flutterViewController = FlutterViewController(project: project)
    self.contentViewController = flutterViewController

    // Sensible default + minimum window size, centered on screen.
    // Default 1440×880, shrunk to fit smaller screens (e.g. a 13" laptop).
    var initialSize = NSSize(width: 1440, height: 880)
    if let visible = NSScreen.main?.visibleFrame.size {
      initialSize.width = min(initialSize.width, visible.width - 40)
      initialSize.height = min(initialSize.height, visible.height - 40)
    }
    self.setContentSize(initialSize)
    self.contentMinSize = NSSize(width: 1180, height: 640)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
