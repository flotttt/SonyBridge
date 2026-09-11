import SwiftUI

// A title with a switch on the right (Focus on Voice, DSEE, Speak-to-Chat, Adaptive Volume).
struct ToggleRow: View {
    @ObservedObject var model: HeadphonesModel
    let title: String
    var indent: CGFloat = MenuMetrics.leading
    let isOn: (HeadphonesModel) -> Bool
    let set: (HeadphonesModel, Bool) -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { isOn(model) }, set: { set(model, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.leading, indent)
        .padding(.trailing, MenuMetrics.trailing)
        .padding(.vertical, 2)
        .disabled(!model.connected)
        .opacity(model.connected ? 1 : 0.5)
    }
}
