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

    // MARK: - Connection

    // User-initiated: uses the already-connected Sony headset, else the macOS Bluetooth picker.
    func connect() {
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
        stopTimers()
        bridge.disconnect()
        connectionState = .disconnected
    }

    func handleConnectResult(ok: Bool, error: String?, userInitiated: Bool) {
        guard ok else {
            connectionState = .disconnected
            if userInitiated, let error = error { errorMessage = error }
            return
        }
        connectionState = .connected
        syncFromBridge()
        bridge.refreshStatus { [weak self] in self?.syncFromBridge() } // called after reads, then after probes
        startTimers()
    }

    // The control link dropped on its own (idle power-save). Task 7 adds the automatic reconnection here.
    func linkLost() {
        stopTimers()
        connectionState = .disconnected
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
        readAmbientFromBridge()
        readBatteryFromBridge()
        supportsEqualizer = bridge.supportsEqualizer
        equalizerWritable = bridge.equalizerWritable
        eqPreset = bridge.eqPreset
        eqHasClearBass = bridge.equalizerHasClearBass
        clearBass = bridge.clearBass
        eqBands = (0..<bridge.equalizerBandCount).map { bridge.equalizerBand(at: $0) }
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
