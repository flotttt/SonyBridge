import AppKit

// Entry point: a menu bar-only app (LSUIElement), no window and no Dock icon.
@main
enum SonyBridgeApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
