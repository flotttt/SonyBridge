import Foundation
import Combine

enum ConnectionState {
    case disconnected, connecting, connected
}

// Observable state of the headphones and the actions the menu triggers. Wraps the Obj-C++ HeadphonesBridge.
final class HeadphonesModel: ObservableObject {
    private enum PolledSetting { case ambient }

    private let bridge = HeadphonesBridge()

    @Published private(set) var connectionState: ConnectionState = .disconnected
    var connected: Bool { connectionState == .connected }

    // Kept after a disconnect so the header still names the last headset.
    @Published private(set) var deviceName = ""
    @Published private(set) var deviceMac = ""
    @Published private(set) var protocolVersion = ""
    @Published private(set) var firmware = ""
    @Published private(set) var codec = ""
    @Published private(set) var maxAmbientLevel = 20

    @Published private(set) var mode: SHCAmbientMode = .off
    @Published private(set) var ambientLevel = 10
    @Published private(set) var focusOnVoice = false

    @Published private(set) var batteryLevel = -1
    @Published private(set) var batteryCharging = false
    @Published private(set) var hasDualBattery = false
    @Published private(set) var batteryLeft = -1
    @Published private(set) var batteryRight = -1
    @Published private(set) var batteryCase = -1

    @Published private(set) var supportsEqualizer = false
    @Published private(set) var equalizerWritable = false
    @Published private(set) var eqPreset = 0
    @Published private(set) var eqBands: [Int] = []
    @Published private(set) var eqHasClearBass = false
    @Published private(set) var clearBass = 0
    @Published private(set) var hasDsee = false
    @Published private(set) var dsee = false

    @Published private(set) var hasAutoPowerOff = false
    @Published private(set) var autoPowerOff = 0
    @Published private(set) var hasSpeakToChat = false
    @Published private(set) var speakToChat = false
    @Published private(set) var hasAdaptiveVolume = false
    @Published private(set) var adaptiveVolume = false

    // Last error from a user action; cleared by the next successful one.
    @Published private(set) var errorMessage: String?

    private var timers: [Timer] = []
    private var pollGuard = PollGuard<PolledSetting>()
    private var levelThrottle = SendThrottle()
    private var eqThrottle = SendThrottle()

    // Set by AppDelegate; nil means "no automatic behaviour".
    var settings: AppSettings?
    private var reconnectPolicy = ReconnectPolicy()
    private var reconnectTimer: Timer?
    private var reconnectAddress: String?
    private var userDisconnected = false // after "Déconnecter": no auto-reconnect until the headset reconnects to macOS

    // MARK: - Connection

    // User-initiated: uses the already-connected Sony headset, else the macOS Bluetooth picker.
    func connect() {
        userDisconnected = false
        cancelReconnect()
        connectionState = .connecting
        errorMessage = nil
        // Defer so the menu can show "Connecting…" before a modal picker blocks the main thread.
        DispatchQueue.main.async {
            self.bridge.scanAndConnect { ok, error in
                self.handleConnectResult(ok: ok, error: error, userInitiated: true)
            }
        }
    }

    func disconnect() {
        userDisconnected = true
        cancelReconnect()
        stopTimers()
        bridge.disconnect()
        connectionState = .disconnected
    }

    func handleConnectResult(ok: Bool, error: String?, userInitiated: Bool) {
        guard ok else {
            connectionState = .disconnected
            if userInitiated, let error = error { errorMessage = error }
            if !userInitiated && reconnectAddress != nil {
                // Only keep retrying while the option is still on; the user may have turned it off meanwhile.
                if settings?.autoReconnect == true { scheduleReconnect() } else { cancelReconnect() }
            }
            return
        }
        cancelReconnect()
        connectionState = .connected
        errorMessage = nil // a failed manual attempt's error must not stay under a "Connected" header
        syncFromBridge()
        settings?.lastDeviceAddress = deviceMac
        bridge.refreshStatus { [weak self] in self?.syncFromBridge() } // called after reads, then after probes
        startTimers()
    }

    // The control link dropped on its own (idle power-save): retry while the headset is still connected to macOS.
    func linkLost() {
        stopTimers()
        bridge.disconnect() // resets sequence numbers and buffers for the next connection
        connectionState = .disconnected
        guard settings?.autoReconnect == true, !userDisconnected, !deviceMac.isEmpty else { return }
        reconnectAddress = deviceMac
        scheduleReconnect()
    }

    // MARK: - Automatic connection

    // Not user-initiated: failures stay silent (normal while the headset sleeps).
    func autoConnect(toAddress address: String) {
        guard connectionState == .disconnected else { return }
        // With Reconnect Automatically on, a failed attempt (launch, DeviceWatcher) is retried by the failure
        // path's scheduleReconnect() while the headset stays connected to macOS.
        if settings?.autoReconnect == true { reconnectAddress = address }
        connectionState = .connecting
        bridge.connect(toAddress: address) { ok, error in
            self.handleConnectResult(ok: ok, error: error, userInitiated: false)
        }
    }

    // At launch: the last headset if macOS has it connected, else any connected Sony headset.
    func autoConnectOnLaunch() {
        let remembered = settings?.lastDeviceAddress.flatMap { HeadphonesBridge.isDeviceConnectedToMac($0) ? $0 : nil }
        if let address = remembered ?? HeadphonesBridge.connectedSonyHeadsetAddress() {
            autoConnect(toAddress: address)
        }
    }

    // DeviceWatcher: a device just connected to macOS.
    func headsetConnectedToMac(address: String, name: String) {
        guard settings?.autoConnect == true, HeadphonesBridge.looksLikeSonyHeadset(name),
              connectionState == .disconnected else { return }
        userDisconnected = false
        cancelReconnect()
        // Give the audio link ~2 s to settle before opening the control channel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            // The option or the device's own connection may have changed during the delay; re-check both.
            guard self.settings?.autoConnect == true, HeadphonesBridge.isDeviceConnectedToMac(address) else { return }
            self.autoConnect(toAddress: address)
        }
    }

    // DeviceWatcher: a device left macOS; stop retrying it (headsetConnectedToMac takes over when it's back).
    func headsetDisconnectedFromMac(address: String) {
        if address == reconnectAddress { cancelReconnect() }
    }

    func cancelReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectAddress = nil
        reconnectPolicy.reset()
    }

    private func scheduleReconnect() {
        guard let address = reconnectAddress else { return }
        reconnectTimer?.invalidate()
        let timer = Timer(timeInterval: reconnectPolicy.nextDelay(), repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // The user may have turned the option off while this attempt was pending.
            guard self.settings?.autoReconnect == true else { self.cancelReconnect(); return }
            guard HeadphonesBridge.isDeviceConnectedToMac(address) else { self.cancelReconnect(); return }
            self.autoConnect(toAddress: address)
        }
        RunLoop.main.add(timer, forMode: .common)
        reconnectTimer = timer
    }

    // MARK: - Actions

    func setMode(_ newMode: SHCAmbientMode) {
        mode = newMode
        pollGuard.userChanged(.ambient)
        pushAmbient()
    }

    func setLevel(_ level: Int, final: Bool) {
        ambientLevel = level
        pollGuard.userChanged(.ambient)
        if mode == .ambientSound && levelThrottle.shouldSend(final: final) { pushAmbient() }
    }

    func setFocusOnVoice(_ on: Bool) {
        focusOnVoice = on
        pollGuard.userChanged(.ambient)
        pushAmbient()
    }

    func setEqualizerPreset(_ preset: Int) {
        eqPreset = preset
        bridge.setEqualizerPreset(preset) { [weak self] ok, error in self?.finish(ok, error) }
    }

    func setEqualizerBand(_ index: Int, value: Int, final: Bool) {
        guard eqBands.indices.contains(index) else { return }
        eqBands[index] = value
        eqPreset = 0xA0
        if eqThrottle.shouldSend(final: final) { pushCustomEqualizer() }
    }

    func setClearBass(_ value: Int, final: Bool) {
        clearBass = value
        eqPreset = 0xA0
        if eqThrottle.shouldSend(final: final) { pushCustomEqualizer() }
    }

    func resetEqualizer() {
        eqBands = Array(repeating: 0, count: eqBands.count)
        clearBass = 0
        eqPreset = 0xA0
        pushCustomEqualizer()
    }

    func setDsee(_ on: Bool) {
        dsee = on
        bridge.setDsee(on) { [weak self] ok, error in self?.finish(ok, error) }
    }

    func setAutoPowerOff(_ index: Int) {
        autoPowerOff = index
        bridge.setAutoPowerOff(index) { [weak self] ok, error in self?.finish(ok, error) }
    }

    func setSpeakToChat(_ on: Bool) {
        speakToChat = on
        bridge.setSpeakToChat(on) { [weak self] ok, error in self?.finish(ok, error) }
    }

    func setAdaptiveVolume(_ on: Bool) {
        adaptiveVolume = on
        bridge.setAdaptiveVolume(on) { [weak self] ok, error in self?.finish(ok, error) }
    }

    func showError(_ message: String) {
        errorMessage = message
    }

    private func pushAmbient() {
        bridge.applyMode(mode, level: ambientLevel, focusVoice: focusOnVoice) { [weak self] ok, error in
            self?.finish(ok, error)
        }
    }

    private func pushCustomEqualizer() {
        bridge.setCustomEqualizerBass(clearBass, bands: eqBands.map { NSNumber(value: $0) }) { [weak self] ok, error in
            self?.finish(ok, error)
        }
    }

    private func finish(_ ok: Bool, _ error: String?) {
        errorMessage = ok ? nil : error
    }

    // MARK: - Polling

    private func startTimers() {
        stopTimers()
        timers = [
            repeating(every: 1.5) { [weak self] in self?.checkLink() },
            repeating(every: 2) { [weak self] in self?.pollAmbient() },
            repeating(every: 60) { [weak self] in self?.pollBattery() },
        ]
    }

    private func stopTimers() {
        timers.forEach { $0.invalidate() }
        timers = []
    }

    // Added in .common mode so they keep firing while the menu is open (menus run the event-tracking mode).
    private func repeating(every interval: TimeInterval, _ block: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in block() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func checkLink() {
        if connected && !bridge.connected { linkLost() }
    }

    // Follows the headset's own NC button, unless the user just changed the mode from the menu.
    private func pollAmbient() {
        guard connected, pollGuard.shouldAcceptPoll(for: .ambient) else { return }
        bridge.refreshDynamic { [weak self] in
            guard let self = self, self.pollGuard.shouldAcceptPoll(for: .ambient) else { return }
            self.readAmbientFromBridge()
        }
    }

    private func pollBattery() {
        guard connected else { return }
        bridge.refreshBattery { [weak self] in self?.readBatteryFromBridge() }
    }

    // MARK: - Reading the bridge

    private func syncFromBridge() {
        deviceName = bridge.deviceName ?? deviceName
        deviceMac = bridge.deviceMac ?? deviceMac
        protocolVersion = bridge.protocolVersionString ?? ""
        maxAmbientLevel = bridge.maxAmbientLevel
        // refreshStatus calls this twice (the second ~12 s after connect): don't undo a mode change the user
        // made meanwhile.
        if pollGuard.shouldAcceptPoll(for: .ambient) { readAmbientFromBridge() }
        readBatteryFromBridge()
        supportsEqualizer = bridge.supportsEqualizer
        equalizerWritable = bridge.equalizerWritable
        eqPreset = bridge.eqPreset
        eqHasClearBass = bridge.equalizerHasClearBass
        clearBass = bridge.clearBass
        eqBands = (0..<bridge.equalizerBandCount).map { bridge.equalizerBand(at: $0) }
        hasDsee = bridge.hasDsee
        dsee = bridge.dsee
        hasAutoPowerOff = bridge.hasAutoPowerOff
        autoPowerOff = bridge.autoPowerOff
        hasSpeakToChat = bridge.hasSpeakToChat
        speakToChat = bridge.speakToChat
        hasAdaptiveVolume = bridge.hasAdaptiveVolume
        adaptiveVolume = bridge.adaptiveVolume
        firmware = bridge.firmware ?? ""
        codec = bridge.codec ?? ""
    }

    private func readAmbientFromBridge() {
        mode = bridge.mode
        let level = bridge.ambientLevel
        if level > 0 { ambientLevel = level }
        focusOnVoice = bridge.focusOnVoice
    }

    private func readBatteryFromBridge() {
        batteryLevel = bridge.batteryLevel
        batteryCharging = bridge.batteryCharging
        hasDualBattery = bridge.hasDualBattery
        batteryLeft = bridge.batteryLeft
        batteryRight = bridge.batteryRight
        batteryCase = bridge.batteryCase
    }
}
