import SwiftUI

// Ambient Sound level slider (1…max), shown under "Son ambiant".
struct AmbientLevelRow: View {
    @ObservedObject var model: HeadphonesModel

    var body: some View {
        HStack(spacing: 8) {
            Slider(
                value: Binding(get: { Double(model.ambientLevel) },
                               set: { model.setLevel(Int($0.rounded()), final: false) }),
                in: 1...Double(max(model.maxAmbientLevel, 2)),
                step: 1,
                onEditingChanged: { editing in
                    if !editing { model.setLevel(model.ambientLevel, final: true) }
                }
            )
            .controlSize(.small)
            Text(verbatim: "\(model.ambientLevel)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .trailing)
        }
        .padding(.leading, MenuMetrics.indent)
        .padding(.trailing, MenuMetrics.leading)
        .padding(.vertical, 2)
        .disabled(!model.connected)
    }
}
