import AppKit
import Combine

// Owns the menu bar icon and attaches the headphones menu to it.
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let headphonesMenu: HeadphonesMenu
    private var cancellables = Set<AnyCancellable>()

    init(model: HeadphonesModel) {
        headphonesMenu = HeadphonesMenu(model: model)
        statusItem.menu = headphonesMenu.menu
        let image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "SonyBridge")
        image?.isTemplate = true
        statusItem.button?.image = image
        model.$connected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in self?.statusItem.button?.appearsDisabled = !connected }
            .store(in: &cancellables)
    }
}
