import AppKit
import SwiftUI

// Manual equalizer: 10 vertical sliders (WH-1000XM6) or Clear Bass + 5 (older models). Active only on "Manual"
// and when the device's write format is verified (model.equalizerWritable).
struct EqualizerRow: View {
    @ObservedObject var model: HeadphonesModel

    private static let labels5 = ["400", "1k", "2.5k", "6.3k", "16k"]
    private static let labels10 = ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    private var editable: Bool { model.connected && model.equalizerWritable && model.eqPreset == 0xA0 }
    private var labels: [String] { model.eqBands.count == 10 ? Self.labels10 : Self.labels5 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if model.eqHasClearBass {
                band(tr("Clear Bass"), value: model.clearBass) { model.setClearBass($0, final: $1) }
            }
            ForEach(Array(model.eqBands.enumerated()), id: \.offset) { index, value in
                band(index < labels.count ? labels[index] : "", value: value) {
                    model.setEqualizerBand(index, value: $0, final: $1)
                }
            }
        }
        .padding(.leading, MenuMetrics.leading)
        .padding(.trailing, MenuMetrics.trailing)
        .padding(.vertical, 6)
        .frame(height: MenuMetrics.equalizerHeight)
    }

    private func band(_ label: String, value: Int, onChange: @escaping (Int, Bool) -> Void) -> some View {
        VStack(spacing: 3) {
            VerticalBandSlider(value: value, enabled: editable, onChange: onChange)
                .frame(width: 20, height: 72)
            Text(verbatim: label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// A native vertical NSSlider in -10…10. onChange(value, final): final is true on mouse-up.
struct VerticalBandSlider: NSViewRepresentable {
    let value: Int
    let enabled: Bool
    let onChange: (Int, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: Double(value), minValue: -10, maxValue: 10,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.isVertical = true
        slider.isContinuous = true
        slider.controlSize = .small
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.onChange = onChange
        if Int(slider.doubleValue.rounded()) != value { slider.doubleValue = Double(value) }
        slider.isEnabled = enabled
    }

    final class Coordinator: NSObject {
        var onChange: (Int, Bool) -> Void

        init(onChange: @escaping (Int, Bool) -> Void) {
            self.onChange = onChange
        }

        @objc func changed(_ sender: NSSlider) {
            let final = NSApp.currentEvent?.type == .leftMouseUp
            onChange(Int(sender.doubleValue.rounded()), final)
        }
    }
}
