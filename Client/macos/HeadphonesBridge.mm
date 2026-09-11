//
//  HeadphonesBridge.mm
//  Obj-C++ implementation owning the C++ core. Mirrors the connect/apply flow the old ViewController had.
//

#import "HeadphonesBridge.h"
#import <IOBluetoothUI/IOBluetoothUI.h>
#import <IOBluetooth/IOBluetooth.h>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <memory>
#include "MacOSBluetoothConnector.h"
#include "BluetoothWrapper.h"
#include "Headphones.h"
// RecoverableException comes in transitively via BluetoothWrapper.h -> IBluetoothConnector.h -> Exceptions.h.
// (Exceptions.h isn't a project file reference, so it can't be #included directly from this directory.)

// What a background block captures: the session's Headphones object plus the bridge's session generation at
// dispatch time. One BluetoothWrapper serves the whole app lifetime, so after a disconnect a previous
// session's queued work would otherwise keep running on whatever link comes next (possibly a v1 headset,
// where the v2 battery inquiry 0x22 is POWER_OFF). Blocks call isCurrent() before every headphones call and
// stop once the session ended.
struct SHCSession {
    std::shared_ptr<Headphones> hp;
    std::shared_ptr<std::atomic<uint64_t>> generation;
    uint64_t token;
    bool isCurrent() const { return generation->load() == token; }
};

// Runs a finished block's completion on the main queue, unless its session ended meanwhile: the data it
// would publish belongs to a previous connection. No caller waits on these completions.
static void SHCCompleteOnMain(SHCSession session, void (^completion)(void)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (session.isCurrent()) completion();
    });
}

static void SHCFinishOnMain(SHCSession session, BOOL ok, NSString * _Nullable error,
                            void (^completion)(BOOL, NSString * _Nullable)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (session.isCurrent()) completion(ok, error);
    });
}

// Core exceptions carry English developer text ("recv timed out", "No ACK received from device", ...): log it,
// show a translated message instead.
static NSString *SHCCommandError(const std::exception &exc) {
    fprintf(stderr, "[error] %s\n", exc.what());
    return NSLocalizedString(@"The headphones didn't respond.", nil);
}

static NSString *SHCConnectionError(const std::exception &exc) {
    fprintf(stderr, "[error] %s\n", exc.what());
    return NSLocalizedString(@"Couldn't open the control channel.", nil);
}

@implementation HeadphonesBridge {
    std::unique_ptr<BluetoothWrapper> _bt;
    // shared_ptr: background blocks capture their own copy so a disconnect()-triggered _hp.reset() on the
    // main thread can't free the object while a queued block is still mid-way through a read/write.
    // One Headphones object per connection session (it also holds that session's "initialized" flag).
    std::shared_ptr<Headphones> _hp;
    // Session generation, bumped when a session ends or starts; see SHCSession. shared_ptr so blocks can
    // hold it without retaining self.
    std::shared_ptr<std::atomic<uint64_t>> _generation;
    NSString *_deviceName;
    NSString *_deviceMac;
    // All user-initiated commands run on this SERIAL queue so quick successive taps reach the device in
    // order (a concurrent queue let them race and land out of order).
    dispatch_queue_t _cmdQueue;
}

- (instancetype)init {
    if ((self = [super init])) {
        _bt = std::make_unique<BluetoothWrapper>(std::make_unique<MacOSBluetoothConnector>());
        _generation = std::make_shared<std::atomic<uint64_t>>(0);
        _cmdQueue = dispatch_queue_create("com.sonybridge.commands", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

// Main thread only (reads _hp).
- (SHCSession)currentSession {
    return SHCSession{ _hp, _generation, _generation->load() };
}

// Invalidates every block captured so far: they stop before their next headphones call.
- (void)bumpSession {
    _generation->fetch_add(1);
}

- (BOOL)connected {
    return _bt && _bt->isConnected();
}

- (nullable NSString *)deviceName {
    return _deviceName;
}

- (nullable NSString *)deviceMac {
    return _deviceMac;
}

- (nullable NSString *)protocolVersionString {
    if (!self.connected) return nil;
    return _bt->getProtocolVersion() == SonyProtocolVersion::V2 ? @"v2" : @"v1";
}

- (BOOL)supportsVpt {
    if (!self.connected) return NO;
    return _bt->getProtocolVersion() == SonyProtocolVersion::V1;
}

- (NSInteger)maxAmbientLevel {
    if (self.connected && _bt->getProtocolVersion() == SonyProtocolVersion::V2) return 20;
    return 19;
}

- (SHCAmbientMode)mode {
    if (!_hp) return SHCAmbientModeOff;
    if (!_hp->getAmbientSoundControl()) return SHCAmbientModeOff;
    return _hp->getAsmLevel() > 0 ? SHCAmbientModeAmbientSound : SHCAmbientModeNoiseCanceling;
}

- (NSInteger)ambientLevel {
    return _hp ? _hp->getAsmLevel() : 0;
}

- (BOOL)focusOnVoice {
    return _hp ? _hp->getFocusOnVoice() : NO;
}

- (BOOL)focusOnVoiceAvailable {
    return _hp ? _hp->isFocusOnVoiceAvailable() : NO;
}

- (NSInteger)batteryLevel {
    return _hp ? _hp->getBatteryLevel() : -1;
}

- (BOOL)batteryCharging {
    return _hp ? _hp->isBatteryCharging() : NO;
}

- (BOOL)hasDualBattery { return _hp && _hp->hasDualBattery(); }
- (NSInteger)batteryLeft { return _hp ? _hp->getBatteryLeft() : -1; }
- (NSInteger)batteryRight { return _hp ? _hp->getBatteryRight() : -1; }
- (NSInteger)batteryCase { return _hp ? _hp->getBatteryCase() : -1; }

- (NSInteger)eqPreset {
    return _hp ? (NSInteger)_hp->getEqualizerPreset() : 0;
}

- (BOOL)supportsEqualizer {
    return self.connected && _bt->getProtocolVersion() == SonyProtocolVersion::V2;
}

- (NSInteger)clearBass {
    return _hp ? _hp->getClearBass() : 0;
}

- (NSInteger)equalizerBandCount { return _hp ? _hp->getEqualizerBandCount() : 0; }
- (BOOL)equalizerHasClearBass { return _hp && _hp->equalizerHasClearBass(); }
// Only the 5-band + Clear Bass layout (WH-CH720N family) has a verified write format.
- (BOOL)equalizerWritable { return self.supportsEqualizer && _hp && _hp->equalizerHasClearBass(); }

- (BOOL)hasDsee { return _hp && _hp->hasDsee(); }

- (BOOL)dsee {
    return _hp ? _hp->getDsee() : NO;
}

- (NSInteger)equalizerBandAtIndex:(NSInteger)index {
    return _hp ? _hp->getEqualizerBand((int)index) : 0;
}

- (BOOL)hasAutoPowerOff { return _hp && _hp->hasAutoPowerOff(); }
- (NSInteger)autoPowerOff { return _hp ? _hp->getAutoPowerOff() : 0; }
- (BOOL)hasFirmware { return _hp && _hp->hasFirmware(); }
- (nullable NSString *)firmware { return _hp ? @(_hp->getFirmware().c_str()) : nil; }
- (BOOL)hasCodec { return _hp && _hp->hasCodec(); }
- (nullable NSString *)codec { return _hp ? @(_hp->getCodec().c_str()) : nil; }
- (BOOL)hasSpeakToChat { return _hp && _hp->hasSpeakToChat(); }
- (BOOL)speakToChat { return _hp && _hp->getSpeakToChat(); }
- (BOOL)hasAdaptiveVolume { return _hp && _hp->hasAdaptiveVolume(); }
- (BOOL)adaptiveVolume { return _hp && _hp->getAdaptiveVolume(); }

static BOOL SHCLooksLikeSonyHeadset(NSString *name) {
    if (name.length == 0) return NO;
    NSArray<NSString *> *prefixes = @[@"WH-", @"WF-", @"WI-", @"MDR-", @"XB", @"LinkBuds"];
    for (NSString *p in prefixes) {
        if ([name hasPrefix:p] || [name containsString:p]) return YES;
    }
    return NO;
}

- (void)scanAndConnectWithCompletion:(void (^)(BOOL, NSString * _Nullable))completion {
    // Prefer the already system-connected Sony headset (Sony-app "My Device" behaviour) and skip the
    // native picker, which shows a confusing empty list when nothing is connected.
    IOBluetoothDevice *device = nil;
    for (IOBluetoothDevice *paired in [IOBluetoothDevice pairedDevices]) {
        if ([paired isConnected] && SHCLooksLikeSonyHeadset([paired name])) {
            device = paired;
            break;
        }
    }

    if (!device) {
        // Fall back to the native picker if we can't auto-identify a connected Sony device.
        IOBluetoothDeviceSelectorController *selector = [IOBluetoothDeviceSelectorController deviceSelector];
        if ([selector runModal] != kIOBluetoothUISuccess) {
            completion(NO, nil); // user cancelled - not an error
            return;
        }
        device = [[selector getResults] lastObject];
    }

    if (!device) {
        completion(NO, NSLocalizedString(@"No connected Sony headset found. Connect your headphones in macOS Bluetooth settings first.", nil));
        return;
    }

    [self connectDevice:device completion:completion];
}

- (void)connectDevice:(IOBluetoothDevice *)device completion:(void (^)(BOOL, NSString * _Nullable))completion {
    // A connection attempt ends whatever session came before: its queued work stops before its next call,
    // and no refresh can pair the new link with the old Headphones object while the link opens.
    _hp.reset();
    [self bumpSession];

    try {
        _bt->connect([[device addressString] UTF8String]);
    } catch (std::exception &exc) {
        completion(NO, SHCConnectionError(exc));
        return;
    }

    // A real RFCOMM open (SDP + link setup, sometimes with encryption renegotiation) can take a few
    // seconds; pump the run loop until it lands or we give up.
    int timeout = 80;
    while (!_bt->isConnected() && timeout >= 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        timeout--;
    }

    if (!_bt->isConnected()) {
        _bt->disconnect();
        completion(NO, NSLocalizedString(@"Connection timed out.", nil));
        return;
    }

    _deviceName = [device nameOrAddress];
    _deviceMac = [device addressString];
    // New session: a fresh Headphones object (not initialized yet) and a new generation.
    _hp = std::make_shared<Headphones>(*_bt);
    [self bumpSession];
    completion(YES, nil);
}

+ (BOOL)looksLikeSonyHeadset:(NSString *)name {
    return SHCLooksLikeSonyHeadset(name);
}

+ (nullable NSString *)connectedSonyHeadsetAddress {
    for (IOBluetoothDevice *paired in [IOBluetoothDevice pairedDevices]) {
        if ([paired isConnected] && SHCLooksLikeSonyHeadset([paired name])) return [paired addressString];
    }
    return nil;
}

+ (BOOL)isDeviceConnectedToMac:(NSString *)address {
    IOBluetoothDevice *device = [IOBluetoothDevice deviceWithAddressString:address];
    return device != nil && [device isConnected];
}

- (void)connectToAddress:(NSString *)address completion:(void (^)(BOOL, NSString * _Nullable))completion {
    IOBluetoothDevice *device = [IOBluetoothDevice deviceWithAddressString:address];
    if (!device) {
        completion(NO, NSLocalizedString(@"Not connected.", nil));
        return;
    }
    [self connectDevice:device completion:completion];
}

- (void)disconnect {
    // First, so this session's queued work stops before its next headphones call.
    [self bumpSession];
    if (_bt) _bt->disconnect();
    _hp.reset();
    _deviceName = nil;
    _deviceMac = nil;
}

- (void)refreshStatusWithCompletion:(void (^)(void))completion {
    if (!_hp || !self.connected) { completion(); return; }
    SHCSession session = [self currentSession];
    // CRITICAL: the init/battery/EQ inquiries below use v2 opcodes. Opcode 0x22 is BATTERY_LEVEL_REQUEST
    // on v2 but POWER_OFF on v1 - sending it to a v1 device (e.g. WH-1000XM4) powers the headphones off.
    // A v1 device still needs *some* valid handshake traffic right after connect or it drops/powers off on
    // its own, so read its ambient state (read-only 66 02) instead of sending nothing.
    // This dispatch-time check only picks the path: the session check stops the block once this session
    // ended, and Headphones re-checks the live protocol before every v2-only frame.
    if (_bt->getProtocolVersion() != SonyProtocolVersion::V2) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (!session.isCurrent()) return;
            try { session.hp->requestAmbientState(); } catch (std::exception &) {}
            SHCCompleteOnMain(session, completion);
        });
        return;
    }
    // Reads run on the global queue (not the serial command queue) so they don't block quick user taps;
    // per-call the connector mutex still serializes actual I/O.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        Headphones *hp = session.hp.get(); // kept alive by the block's session copy
        // Fast, always-supported reads first, then update the UI immediately...
        // Each read is independent: one lost frame (recv timeout) must not skip the others, or a fresh
        // connection stays half-initialized (no battery, no EQ, NC/ASM polled on the wrong channel).
        if (!hp->isInitialized()) {
            for (int attempt = 0; attempt < 2 && !hp->isInitialized(); attempt++) {
                if (!session.isCurrent()) return;
                try { hp->initDevice(); } catch (std::exception &) {}
            }
            // Probe even if init never answered, so the NC/ASM channel is still picked (catches internally).
            if (!session.isCurrent()) return;
            hp->probeNcAsmInquiryType();
        }
        // Current NC/ASM state, on the channel probeNcAsmInquiryType() picked.
        if (!session.isCurrent()) return;
        try { hp->requestAmbientState(); } catch (std::exception &) {}
        if (!session.isCurrent()) return;
        try { hp->requestBattery(); } catch (std::exception &) {}
        if (!session.isCurrent()) return;
        try { hp->requestEqualizer(); } catch (std::exception &) {}
        if (!session.isCurrent()) return;
        try { hp->requestDsee(); } catch (std::exception &) {}
        SHCCompleteOnMain(session, completion);

        // ...then the optional-feature probes, which can each take a couple seconds to time out on a
        // device that doesn't support them. Update the UI again once they've settled.
        if (!session.isCurrent()) return;
        try { hp->probeCapabilities(); } catch (std::exception &) {}
        SHCCompleteOnMain(session, completion);
    });
}

- (void)refreshDynamicWithCompletion:(void (^)(void))completion {
    if (!_hp || !self.connected) { completion(); return; }
    SHCSession session = [self currentSession];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // The headphone's physical button only changes ambient/NC, so that's all we poll (keeps traffic low).
        // requestAmbientState() is protocol-aware (v2 uses 66 17, v1 uses 66 02), so this is safe on both.
        if (!session.isCurrent()) return;
        try { session.hp->requestAmbientState(); } catch (std::exception &) {}
        SHCCompleteOnMain(session, completion);
    });
}

- (void)refreshBatteryWithCompletion:(void (^)(void))completion {
    // CRITICAL: 0x22 is BATTERY_LEVEL_REQUEST on v2 but POWER_OFF on v1 - never send it to a v1 device.
    if (!_hp || !self.connected || _bt->getProtocolVersion() != SonyProtocolVersion::V2) { completion(); return; }
    SHCSession session = [self currentSession];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (!session.isCurrent()) return;
        try { session.hp->requestBattery(); } catch (std::exception &) {}
        SHCCompleteOnMain(session, completion);
    });
}

- (void)setEqualizerPreset:(NSInteger)preset completion:(void (^)(BOOL, NSString * _Nullable))completion {
    if (!_hp || !self.connected) {
        completion(NO, NSLocalizedString(@"Not connected.", nil));
        return;
    }
    // The v2 EQ SET opcode differs from v1; only issue it on confirmed v2 devices.
    if (!self.equalizerWritable) {
        completion(NO, NSLocalizedString(@"Equalizer control isn't supported on this device yet.", nil));
        return;
    }
    SHCSession session = [self currentSession];
    dispatch_async(_cmdQueue, ^{
        if (!session.isCurrent()) return;
        NSString *error = nil;
        BOOL ok = YES;
        try {
            session.hp->setEqualizerPreset(static_cast<EQ_PRESET>((unsigned char)preset));
        } catch (std::exception &exc) {
            ok = NO;
            error = SHCCommandError(exc);
        }
        SHCFinishOnMain(session, ok, error, completion);
    });
}

- (void)setCustomEqualizerBass:(NSInteger)bass bands:(NSArray<NSNumber *> *)bands completion:(void (^)(BOOL, NSString * _Nullable))completion {
    if (!_hp || !self.connected || !self.equalizerWritable) {
        completion(NO, NSLocalizedString(@"Equalizer control isn't supported on this device yet.", nil));
        return;
    }
    std::vector<int> cbands;
    for (NSNumber *n in bands) cbands.push_back((int)n.integerValue);
    int cbass = (int)bass;
    SHCSession session = [self currentSession];
    dispatch_async(_cmdQueue, ^{
        if (!session.isCurrent()) return;
        NSString *error = nil; BOOL ok = YES;
        try {
            session.hp->setEqualizerCustom(cbass, cbands);
        } catch (std::exception &exc) { ok = NO; error = SHCCommandError(exc); }
        SHCFinishOnMain(session, ok, error, completion);
    });
}

- (void)setDsee:(BOOL)enabled completion:(void (^)(BOOL, NSString * _Nullable))completion {
    if (!_hp || !self.connected || _bt->getProtocolVersion() != SonyProtocolVersion::V2) {
        completion(NO, NSLocalizedString(@"Not supported on this device.", nil));
        return;
    }
    SHCSession session = [self currentSession];
    dispatch_async(_cmdQueue, ^{
        if (!session.isCurrent()) return;
        NSString *error = nil; BOOL ok = YES;
        try {
            session.hp->setDsee(enabled);
        } catch (std::exception &exc) { ok = NO; error = SHCCommandError(exc); }
        SHCFinishOnMain(session, ok, error, completion);
    });
}

- (void)applyMode:(SHCAmbientMode)mode
            level:(NSInteger)level
       focusVoice:(BOOL)focusVoice
       completion:(void (^)(BOOL, NSString * _Nullable))completion {
    if (!_hp || !self.connected) {
        completion(NO, NSLocalizedString(@"Not connected.", nil));
        return;
    }

    switch (mode) {
        case SHCAmbientModeOff:
            _hp->setAmbientSoundControl(false);
            break;
        case SHCAmbientModeNoiseCanceling:
            _hp->setAmbientSoundControl(true);
            _hp->setAsmLevel(0);
            _hp->setFocusOnVoice(false);
            break;
        case SHCAmbientModeAmbientSound:
            _hp->setAmbientSoundControl(true);
            _hp->setAsmLevel((int)MAX(level, 1));
            _hp->setFocusOnVoice(focusVoice);
            break;
    }

    SHCSession session = [self currentSession];
    dispatch_async(_cmdQueue, ^{
        if (!session.isCurrent()) return;
        NSString *error = nil;
        BOOL ok = YES;
        try {
            if (session.hp->isChanged()) session.hp->setChanges();
        } catch (std::exception &exc) {
            ok = NO;
            error = SHCCommandError(exc);
        }
        SHCFinishOnMain(session, ok, error, completion);
    });
}

- (void)setAutoPowerOff:(NSInteger)index completion:(void (^)(BOOL, NSString * _Nullable))completion {
    if (!_hp || !self.connected) { completion(NO, NSLocalizedString(@"Not connected.", nil)); return; }
    SHCSession session = [self currentSession];
    dispatch_async(_cmdQueue, ^{
        if (!session.isCurrent()) return;
        NSString *error = nil; BOOL ok = YES;
        try { session.hp->setAutoPowerOff((int)index); } catch (std::exception &exc) { ok = NO; error = SHCCommandError(exc); }
        SHCFinishOnMain(session, ok, error, completion);
    });
}

- (void)setSpeakToChat:(BOOL)enabled completion:(void (^)(BOOL, NSString * _Nullable))completion {
    if (!_hp || !self.connected) { completion(NO, NSLocalizedString(@"Not connected.", nil)); return; }
    SHCSession session = [self currentSession];
    dispatch_async(_cmdQueue, ^{
        if (!session.isCurrent()) return;
        NSString *error = nil; BOOL ok = YES;
        try { session.hp->setSpeakToChat(enabled); } catch (std::exception &exc) { ok = NO; error = SHCCommandError(exc); }
        SHCFinishOnMain(session, ok, error, completion);
    });
}

- (void)setAdaptiveVolume:(BOOL)enabled completion:(void (^)(BOOL, NSString * _Nullable))completion {
    if (!_hp || !self.connected) { completion(NO, NSLocalizedString(@"Not connected.", nil)); return; }
    SHCSession session = [self currentSession];
    dispatch_async(_cmdQueue, ^{
        if (!session.isCurrent()) return;
        NSString *error = nil; BOOL ok = YES;
        try { session.hp->setAdaptiveVolume(enabled); } catch (std::exception &exc) { ok = NO; error = SHCCommandError(exc); }
        SHCFinishOnMain(session, ok, error, completion);
    });
}

@end
