import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = HeadphonesModel()
    private let settings = AppSettings()
    private let deviceWatcher = DeviceWatcher()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.settings = settings
        statusItemController = StatusItemController(model: model, settings: settings)

        deviceWatcher.onConnect = { [weak self] address, name in
            self?.model.headsetConnectedToMac(address: address, name: name)
        }
        deviceWatcher.onDisconnect = { [weak self] address in
            self?.model.headsetDisconnectedFromMac(address: address)
        }
        deviceWatcher.start()

        if settings.autoConnect { model.autoConnectOnLaunch() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.disconnect()
    }
}
