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
    static let equalizerHeight: CGFloat = 100 // slider 72 + spacing 3 + label ~11 + vertical paddings 2×6 ~98
    static let leading: CGFloat = 24          // lines up with native item titles
    static let indent: CGFloat = 45           // rows nested under "Son ambiant", aligned with mode titles' text
    static let trailing: CGFloat = 14         // right padding (mirrors the submenu-arrow column)
}

// Wraps a SwiftUI view in a menu item, for rows a plain NSMenuItem can't express (sliders, switches, header).
// Rows keep a fixed height: optional lines (the error line, notes) are separate plain items instead.
// `width` only seeds the initial layout pass used to compute the row's fitting height; the hosted view is
// then made horizontally resizable so it follows the menu's actual width (NSMenu.minimumWidth) instead of
// staying pinned at that initial width while native items stretch the menu wider (or narrower).
func hostingMenuItem<Content: View>(width: CGFloat = MenuMetrics.width, @ViewBuilder _ content: () -> Content) -> NSMenuItem {
    let host = NSHostingView(rootView: content().frame(maxWidth: .infinity, alignment: .leading))
    host.frame = NSRect(x: 0, y: 0, width: width, height: 0)
    host.frame.size.height = host.fittingSize.height
    host.autoresizingMask = [.width]
    let item = NSMenuItem()
    item.view = host
    return item
}

// "Title        value": the value right-aligned in the secondary color, like "Égaliseur        Graves ›".
func titleWithValue(_ title: String, _ value: String, width: CGFloat = MenuMetrics.width - 40) -> NSAttributedString {
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
