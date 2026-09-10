import AppKit

// Menu bar icon: one monochrome SF Symbol per mode, dimmed when disconnected (spec §6.6).
enum StatusIcon {
    static func symbolName(for mode: SHCAmbientMode) -> String {
        switch mode {
        case .noiseCanceling: return "headphones.circle.fill"
        case .ambientSound: return "ear.and.waveform"
        default: return "headphones"
        }
    }

    static func image(connected: Bool, mode: SHCAmbientMode) -> NSImage? {
        let name = connected ? symbolName(for: mode) : "headphones"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "SonyBridge")
            ?? NSImage(systemSymbolName: "headphones", accessibilityDescription: "SonyBridge")
        image?.isTemplate = true // macOS tints it for light/dark menu bars
        return image
    }
}
