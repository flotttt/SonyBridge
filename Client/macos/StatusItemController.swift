import AppKit
import Combine

// Owns the menu bar icon (it follows the mode and connection state) and attaches the headphones menu to it.
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let headphonesMenu: HeadphonesMenu
    private var cancellables = Set<AnyCancellable>()

    init(model: HeadphonesModel, settings: AppSettings) {
        headphonesMenu = HeadphonesMenu(model: model, settings: settings)
        statusItem.menu = headphonesMenu.menu
        model.$connectionState.combineLatest(model.$mode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, mode in
                let connected = state == .connected
                self?.statusItem.button?.image = StatusIcon.image(connected: connected, mode: mode)
                self?.statusItem.button?.appearsDisabled = !connected
            }
            .store(in: &cancellables)
    }
}
