import AppKit
import Combine

// The status item's menu (spec §4). Built once; update() refreshes states, visibility and values in place,
// including while the menu is open.
final class HeadphonesMenu {
    let menu = NSMenu()
    private let model: HeadphonesModel
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    private let errorItem = NSMenuItem()
    private var modeItems: [(SHCAmbientMode, NSMenuItem)] = []
    private var ambientRows: [NSMenuItem] = []            // level slider + focus on voice
    private let equalizerItem = NSMenuItem()
    private var equalizerRowItem = NSMenuItem()
    private var presetItems: [(Int, NSMenuItem)] = []
    private let equalizerNoteItem = NSMenuItem()
    private var equalizerResetItem = NSMenuItem()
    private var dseeItem = NSMenuItem()
    private var speakToChatItem = NSMenuItem()
    private var adaptiveVolumeItem = NSMenuItem()
    private let autoPowerOffItem = NSMenuItem()
    private var autoPowerOffItems: [NSMenuItem] = []
    private let aboutItem = NSMenuItem()
    private let aboutMenu = NSMenu()
    private var aboutValues: [String] = []  // cache to avoid rebuilding About menu on every slider drag
    private var connectItem = NSMenuItem()
    private var launchAtLoginItem = NSMenuItem()
    private var autoConnectItem = NSMenuItem()
    private var autoReconnectItem = NSMenuItem()

    private static var presets: [(Int, String)] {
        [(0x00, tr("Off")), (0x10, tr("Bright")), (0x11, tr("Excited")), (0x12, tr("Mellow")),
         (0x13, tr("Relaxed")), (0x14, tr("Vocal")), (0x15, tr("Treble")), (0x16, tr("Bass")),
         (0x17, tr("Speech")), (0xA0, tr("Manual"))]
    }

    // Index = the bridge's auto power-off option (0=Off, 1=5 min, 2=30 min, 3=1 h, 4=3 h, 5=when taken off).
    // Used for the submenu's item titles (long form).
    private static var autoPowerOffOptions: [String] {
        [tr("Off"), tr("5 min"), tr("30 min"), tr("1 hour"), tr("3 hours"), tr("When taken off")]
    }

    // Same options, but with a short last label - used for the value shown at the right of "Auto Power-Off"
    // itself, since the full "Quand le casque est retiré" collides with the title (spec §4 shows a short
    // value; the submenu keeps the long label).
    private static var autoPowerOffShortOptions: [String] {
        var options = autoPowerOffOptions
        options[options.count - 1] = tr("Taken off")
        return options
    }

    init(model: HeadphonesModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        menu.autoenablesItems = false
        menu.minimumWidth = MenuMetrics.width

        menu.addItem(hostingMenuItem { HeaderRow(model: model) })
        errorItem.isEnabled = false
        menu.addItem(errorItem)
        menu.addItem(.separator())
        addAmbientSection()
        menu.addItem(.separator())
        addSoundSection()
        menu.addItem(.separator())
        addAppSection()

        // objectWillChange fires before the new value is stored; hopping to the main queue reads the new state.
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        update()
    }

    // MARK: - Building

    private func addAmbientSection() {
        menu.addItem(sectionHeader(tr("Ambient Sound Control")))
        let modes: [(SHCAmbientMode, String)] = [
            (.noiseCanceling, tr("Noise Canceling")), (.ambientSound, tr("Ambient Sound")), (.off, tr("Off")),
        ]
        for (mode, title) in modes {
            let item = ActionMenuItem(title) { [weak model] in model?.setMode(mode) }
            item.image = NSImage(systemSymbolName: StatusIcon.symbolName(for: mode), accessibilityDescription: nil)
            modeItems.append((mode, item))
            menu.addItem(item)
            if mode == .ambientSound {
                ambientRows = [
                    hostingMenuItem { AmbientLevelRow(model: model) },
                    hostingMenuItem {
                        ToggleRow(model: model, title: tr("Focus on Voice"), indent: MenuMetrics.indent,
                                  isOn: { $0.focusOnVoice }, set: { $0.setFocusOnVoice($1) })
                    },
                ]
                ambientRows.forEach { menu.addItem($0) }
            }
        }
    }

    private func addSoundSection() {
        let equalizerMenu = NSMenu()
        equalizerMenu.autoenablesItems = false
        equalizerMenu.minimumWidth = MenuMetrics.equalizerWidth
        for (code, title) in Self.presets {
            let item = ActionMenuItem(title) { [weak model] in model?.setEqualizerPreset(code) }
            presetItems.append((code, item))
            equalizerMenu.addItem(item)
        }
        equalizerMenu.addItem(.separator())
        equalizerRowItem = hostingMenuItem(width: MenuMetrics.equalizerWidth) { EqualizerRow(model: model) }
        equalizerMenu.addItem(equalizerRowItem)
        equalizerNoteItem.title = tr("Equalizer changes coming soon for this model")
        equalizerNoteItem.isEnabled = false
        equalizerMenu.addItem(equalizerNoteItem)
        equalizerResetItem = ActionMenuItem(tr("Reset")) { [weak model] in model?.resetEqualizer() }
        equalizerMenu.addItem(equalizerResetItem)
        equalizerItem.submenu = equalizerMenu
        menu.addItem(equalizerItem)

        dseeItem = hostingMenuItem {
            ToggleRow(model: model, title: tr("DSEE"), isOn: { $0.dsee }, set: { $0.setDsee($1) })
        }
        speakToChatItem = hostingMenuItem {
            ToggleRow(model: model, title: tr("Speak-to-Chat"), isOn: { $0.speakToChat }, set: { $0.setSpeakToChat($1) })
        }
        adaptiveVolumeItem = hostingMenuItem {
            ToggleRow(model: model, title: tr("Adaptive Volume"), isOn: { $0.adaptiveVolume }, set: { $0.setAdaptiveVolume($1) })
        }
        for item in [dseeItem, speakToChatItem, adaptiveVolumeItem] { menu.addItem(item) }

        let autoPowerOffMenu = NSMenu()
        autoPowerOffMenu.autoenablesItems = false
        for (index, title) in Self.autoPowerOffOptions.enumerated() {
            let item = ActionMenuItem(title) { [weak model] in model?.setAutoPowerOff(index) }
            autoPowerOffItems.append(item)
            autoPowerOffMenu.addItem(item)
        }
        autoPowerOffItem.submenu = autoPowerOffMenu
        menu.addItem(autoPowerOffItem)
    }

    private func addAppSection() {
        aboutItem.title = tr("About the Headphones")
        aboutMenu.autoenablesItems = false
        aboutItem.submenu = aboutMenu
        menu.addItem(aboutItem)
        let optionsMenu = NSMenu()
        optionsMenu.autoenablesItems = false
        launchAtLoginItem = ActionMenuItem(tr("Launch at Login")) { [weak self] in self?.toggleLaunchAtLogin() }
        autoConnectItem = ActionMenuItem(tr("Connect Automatically")) { [weak settings] in settings?.autoConnect.toggle() }
        autoReconnectItem = ActionMenuItem(tr("Reconnect Automatically")) { [weak settings] in settings?.autoReconnect.toggle() }
        for item in [launchAtLoginItem, autoConnectItem, autoReconnectItem] { optionsMenu.addItem(item) }
        let optionsItem = NSMenuItem(title: tr("SonyBridge Options"), action: nil, keyEquivalent: "")
        optionsItem.submenu = optionsMenu
        menu.addItem(optionsItem)
        connectItem = ActionMenuItem(tr("Connect…")) { [weak self] in self?.toggleConnection() }
        menu.addItem(connectItem)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(tr("Quit SonyBridge"), key: "q") { NSApp.terminate(nil) })
    }

    // MARK: - Updating

    private func update() {
        let connected = model.connected

        errorItem.isHidden = model.errorMessage == nil
        errorItem.title = "⚠︎ " + (model.errorMessage ?? "")

        for (mode, item) in modeItems {
            item.state = connected && model.mode == mode ? .on : .off
            item.isEnabled = connected
        }
        ambientRows.forEach { $0.isHidden = model.mode != .ambientSound }

        equalizerItem.isHidden = !model.supportsEqualizer
        equalizerItem.isEnabled = connected
        equalizerItem.attributedTitle = titleWithValue(tr("Equalizer"), Self.presetName(model.eqPreset))
        for (code, item) in presetItems {
            item.state = model.eqPreset == code ? .on : .off
            item.isEnabled = connected && model.equalizerWritable
        }
        equalizerNoteItem.isHidden = model.equalizerWritable || model.eqBands.isEmpty
        equalizerRowItem.isHidden = model.eqBands.isEmpty
        equalizerResetItem.isEnabled = connected && model.equalizerWritable && model.eqPreset == 0xA0

        dseeItem.isHidden = !model.hasDsee
        speakToChatItem.isHidden = !model.hasSpeakToChat
        adaptiveVolumeItem.isHidden = !model.hasAdaptiveVolume

        let shortOptions = Self.autoPowerOffShortOptions
        autoPowerOffItem.isHidden = !model.hasAutoPowerOff
        autoPowerOffItem.isEnabled = connected
        autoPowerOffItem.attributedTitle = titleWithValue(
            tr("Auto Power-Off"),
            shortOptions.indices.contains(model.autoPowerOff) ? shortOptions[model.autoPowerOff] : "")
        for (index, item) in autoPowerOffItems.enumerated() {
            item.state = index == model.autoPowerOff ? .on : .off
        }

        updateAbout()
        aboutItem.isEnabled = connected

        switch model.connectionState {
        case .connected: connectItem.title = tr("Disconnect")
        case .connecting: connectItem.title = tr("Connecting…")
        case .disconnected: connectItem.title = tr("Connect…")
        }
        connectItem.isEnabled = model.connectionState != .connecting

        launchAtLoginItem.state = settings.launchAtLogin ? .on : .off
        autoConnectItem.state = settings.autoConnect ? .on : .off
        autoReconnectItem.state = settings.autoReconnect ? .on : .off
    }

    private func updateAbout() {
        // update() runs on every model change (slider drags included); rebuild only when a value changed.
        let values = [model.firmware, model.codec, model.protocolVersion, model.deviceMac]
        guard values != aboutValues else { return }
        aboutValues = values

        aboutMenu.removeAllItems()
        let rows: [(String, String)] = [
            (tr("Firmware"), model.firmware), (tr("Codec"), model.codec),
            (tr("Protocol"), model.protocolVersion), (tr("Bluetooth"), model.deviceMac),
        ]
        for (title, value) in rows where !value.isEmpty {
            let item = NSMenuItem()
            item.attributedTitle = titleWithValue(title, value)
            item.isEnabled = false
            aboutMenu.addItem(item)
        }
    }

    private static func presetName(_ code: Int) -> String {
        presets.first { $0.0 == code }?.1 ?? tr("Custom")
    }

    private func toggleLaunchAtLogin() {
        if let error = settings.setLaunchAtLogin(!settings.launchAtLogin) { model.showError(error) }
    }

    private func toggleConnection() {
        if model.connected {
            model.disconnect()
        } else {
            NSApp.activate(ignoringOtherApps: true) // the fallback Bluetooth picker is a modal window
            model.connect()
        }
    }
}
