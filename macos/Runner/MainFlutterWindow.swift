import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The game is laid out for a phone held upright, so open a tall window
    // and keep it from being squashed into landscape.
    self.title = "RGB Invaders"
    self.contentMinSize = NSSize(width: 360, height: 640)
    self.setContentSize(NSSize(width: 480, height: 860))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
