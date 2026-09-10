import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = HeadphonesModel()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(model: model)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.disconnect()
    }
}
