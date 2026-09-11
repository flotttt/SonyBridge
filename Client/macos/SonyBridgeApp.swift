import AppKit

// Entry point: a menu bar-only app (LSUIElement), no window and no Dock icon.
@main
enum SonyBridgeApp {
    static func main() {
        // The app is sandboxed, so it can only write inside the folder allowed by the
        // temporary-exception entitlement. `make run` points it at
        // ~/Library/Logs/SonyBridge/app.log (allowed by that exception); `open --stderr`
        // fails on recent macOS, so the path is passed as a launch argument instead.
        // Redirect stderr to the log file in append mode (unbuffered for live DEBUG hex
        // dumps). freopen() closes stderr before it knows whether the reopen will
        // succeed, so a sandbox denial would leave stderr closed with nothing to fall
        // back to; open()+dup2() only touches stderr once we know the fd is valid.
        if let logPath = UserDefaults.standard.string(forKey: "SonyBridgeLogFile") {
            let fd = open(logPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
            if fd >= 0 {
                dup2(fd, STDERR_FILENO)
                close(fd)
                setvbuf(stderr, nil, _IONBF, 0)
            }
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
