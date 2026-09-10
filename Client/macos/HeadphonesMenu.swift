import AppKit
import Combine

// The status item's menu. Minimal for now: header, modes, connect/disconnect, quit.
final class HeadphonesMenu {
    let menu = NSMenu()
    private let model: HeadphonesModel
    private var cancellables = Set<AnyCancellable>()
    private let headerItem = NSMenuItem()
    private var modeItems: [(SHCAmbientMode, NSMenuItem)] = []
    private var connectItem: ActionMenuItem!

    init(model: HeadphonesModel) {
        self.model = model
        menu.autoenablesItems = false

        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        menu.addItem(sectionHeader(tr("Ambient Sound Control")))
        let modes: [(SHCAmbientMode, String)] = [
            (.noiseCanceling, tr("Noise Canceling")), (.ambientSound, tr("Ambient Sound")), (.off, tr("Off")),
        ]
        for (mode, title) in modes {
            let item = ActionMenuItem(title) { [weak model] in model?.setMode(mode) }
            modeItems.append((mode, item))
            menu.addItem(item)
        }
        menu.addItem(.separator())

        connectItem = ActionMenuItem(tr("Connect…")) { [weak self] in self?.toggleConnection() }
        menu.addItem(connectItem)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(tr("Quit SonyBridge"), key: "q") { NSApp.terminate(nil) })

        // objectWillChange fires before the new value is stored; hopping to the main queue reads the new state.
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        update()
    }

    private func update() {
        let connected = model.connected
        var header = model.deviceName.isEmpty ? "SonyBridge" : model.deviceName
        if connected && model.batteryLevel >= 0 {
            header += " — " + String(format: tr("%ld%%"), model.batteryLevel)
        }
        headerItem.title = header
        for (mode, item) in modeItems {
            item.state = connected && model.mode == mode ? .on : .off
            item.isEnabled = connected
        }
        connectItem.title = connected ? tr("Disconnect") : (model.connectionState == .connecting ? tr("Connecting…") : tr("Connect…"))
        connectItem.isEnabled = model.connectionState != .connecting
    }

    private func toggleConnection() {
        if model.connected {
            model.disconnect()
        } else {
            NSApp.activate(ignoringOtherApps: true) // the fallback Bluetooth picker is a modal window
            model.connect()
        }
    }
}
