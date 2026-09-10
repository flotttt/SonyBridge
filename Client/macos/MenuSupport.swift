import AppKit
import SwiftUI

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

enum MenuMetrics {
    static let width: CGFloat = 280           // main menu rows
    static let equalizerWidth: CGFloat = 300  // equalizer submenu
    static let leading: CGFloat = 14          // lines up with native item titles
    static let indent: CGFloat = 36           // rows nested under "Son ambiant"
}

// Wraps a SwiftUI view in a menu item, for rows a plain NSMenuItem can't express (sliders, switches, header).
// Rows keep a fixed height: optional lines (the error line, notes) are separate plain items instead.
func hostingMenuItem<Content: View>(width: CGFloat = MenuMetrics.width, @ViewBuilder _ content: () -> Content) -> NSMenuItem {
    let host = NSHostingView(rootView: content().frame(width: width, alignment: .leading))
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    let item = NSMenuItem()
    item.view = host
    return item
}

// "Title        value": the value right-aligned in the secondary color, like "Égaliseur        Graves ›".
func titleWithValue(_ title: String, _ value: String, width: CGFloat = MenuMetrics.width - 60) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.tabStops = [NSTextTab(textAlignment: .right, location: width)]
    let font = NSFont.menuFont(ofSize: 0)
    let text = NSMutableAttributedString(string: title, attributes: [.font: font, .paragraphStyle: paragraph])
    if !value.isEmpty {
        text.append(NSAttributedString(string: "\t" + value, attributes: [
            .font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.secondaryLabelColor,
        ]))
    }
    return text
}
