import Foundation
import IOBluetooth

// Reports Bluetooth devices connecting to / disconnecting from macOS, as (address, name).
final class DeviceWatcher: NSObject {
    var onConnect: ((_ address: String, _ name: String) -> Void)?
    var onDisconnect: ((_ address: String) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    func start() {
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] where device.isConnected() {
            if let address = device.addressString { watchDisconnect(device, address: address) }
        }
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        watchDisconnect(device, address: address)
        onConnect?(address, device.name ?? "")
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        guard let address = device.addressString else { return }
        disconnectNotifications[address] = nil
        onDisconnect?(address)
    }

    private func watchDisconnect(_ device: IOBluetoothDevice, address: String) {
        guard disconnectNotifications[address] == nil else { return }
        disconnectNotifications[address] = device.register(forDisconnectNotification: self,
                                                            selector: #selector(deviceDisconnected(_:device:)))
    }
}
