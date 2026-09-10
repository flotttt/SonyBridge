import SwiftUI

// Menu header: headset name, connection state + codec, battery.
struct HeaderRow: View {
    @ObservedObject var model: HeadphonesModel

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.deviceName.isEmpty ? "SonyBridge" : model.deviceName)
                    .font(.system(size: 13, weight: .semibold))
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            if model.connected { battery }
        }
        .padding(.horizontal, MenuMetrics.leading)
        .padding(.vertical, 4)
    }

    private var statusLine: String {
        switch model.connectionState {
        case .connecting: return tr("Connecting…")
        case .disconnected: return tr("Not connected")
        case .connected: return model.codec.isEmpty ? tr("Connected") : "\(tr("Connected")) · \(model.codec)"
        }
    }

    @ViewBuilder private var battery: some View {
        if model.hasDualBattery {
            Text(dualBatteryText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        } else if model.batteryLevel >= 0 {
            HStack(spacing: 4) {
                Text(String(format: tr("%ld%%"), model.batteryLevel))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Image(systemName: batterySymbol)
                    .foregroundColor(model.batteryLevel <= 20 && !model.batteryCharging ? .red : .secondary)
            }
        }
    }

    private var dualBatteryText: String {
        var text = String(format: tr("L %ld%%  R %ld%%"), model.batteryLeft, model.batteryRight)
        if model.batteryCase >= 0 {
            text += "  " + String(format: tr("Case %ld%%"), model.batteryCase)
        }
        return text
    }

    private var batterySymbol: String {
        if model.batteryCharging { return "battery.100.bolt" }
        switch model.batteryLevel {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
