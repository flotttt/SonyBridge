import AppKit

// A menu item that runs a closure (NSMenuItem only supports target/selector natively).
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }
}

// A small grey, non-clickable title above a group of items (like "Contrôle du son ambiant").
func sectionHeader(_ title: String) -> NSMenuItem {
    let item = NSMenuItem()
    item.attributedTitle = NSAttributedString(string: title, attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
        .foregroundColor: NSColor.secondaryLabelColor,
    ])
    item.isEnabled = false
    return item
}
