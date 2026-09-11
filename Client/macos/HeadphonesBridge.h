//
//  HeadphonesBridge.h
//  Pure Objective-C interface over the C++ BluetoothWrapper/Headphones core so SwiftUI can drive it
//  through the bridging header. No C++ types leak into this header.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SHCAmbientMode) {
    SHCAmbientModeOff = 0,
    SHCAmbientModeNoiseCanceling = 1,
    SHCAmbientModeAmbientSound = 2,
};

@interface HeadphonesBridge : NSObject

@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, copy, readonly, nullable) NSString *deviceName;
@property (nonatomic, copy, readonly, nullable) NSString *deviceMac;
@property (nonatomic, copy, readonly, nullable) NSString *protocolVersionString; // "v1" / "v2"

// Only meaningful while connected.
@property (nonatomic, readonly) BOOL supportsVpt;        // v1 protocol devices only
@property (nonatomic, readonly) NSInteger maxAmbientLevel; // 19 (v1) or 20 (v2)

// Current on-device state, mirrored from the last successful command.
@property (nonatomic, readonly) SHCAmbientMode mode;
@property (nonatomic, readonly) NSInteger ambientLevel;
@property (nonatomic, readonly) BOOL focusOnVoice;
@property (nonatomic, readonly) BOOL focusOnVoiceAvailable;

@property (nonatomic, readonly) NSInteger batteryLevel;   // -1 until known
@property (nonatomic, readonly) BOOL batteryCharging;
@property (nonatomic, readonly) BOOL hasDualBattery;      // TWS earbuds
@property (nonatomic, readonly) NSInteger batteryLeft;    // -1 if n/a
@property (nonatomic, readonly) NSInteger batteryRight;
@property (nonatomic, readonly) NSInteger batteryCase;
@property (nonatomic, readonly) NSInteger eqPreset;       // raw preset byte (EQ_PRESET)
@property (nonatomic, readonly) BOOL supportsEqualizer;   // v2 devices only
@property (nonatomic, readonly) NSInteger equalizerBandCount;   // 0 until read, then 5 or 10
@property (nonatomic, readonly) BOOL equalizerHasClearBass;     // 5-band layout
// NO while this device's equalizer write format is unverified (the WH-1000XM6's 10-band layout, spec §7).
@property (nonatomic, readonly) BOOL equalizerWritable;
@property (nonatomic, readonly) NSInteger clearBass;      // -10..10
@property (nonatomic, readonly) BOOL hasDsee;             // the device answered the DSEE inquiry
@property (nonatomic, readonly) BOOL dsee;                // DSEE / audio upsampling

// Optional features (present only if the device answered the capability probe on connect).
@property (nonatomic, readonly) BOOL hasAutoPowerOff;
@property (nonatomic, readonly) NSInteger autoPowerOff;   // 0=Off,1=5m,2=30m,3=1h,4=3h,5=when taken off
@property (nonatomic, readonly) BOOL hasFirmware;
@property (nonatomic, copy, readonly, nullable) NSString *firmware;
@property (nonatomic, readonly) BOOL hasCodec;
@property (nonatomic, copy, readonly, nullable) NSString *codec;
@property (nonatomic, readonly) BOOL hasSpeakToChat;
@property (nonatomic, readonly) BOOL speakToChat;
@property (nonatomic, readonly) BOOL hasAdaptiveVolume;
@property (nonatomic, readonly) BOOL adaptiveVolume;

// Background work and sessions: every async call below captures the current connection session; once it
// ends (disconnect, or a new connection) its queued work stops before the next headphones call and its
// completion is NOT called, so a previous session can never touch the next link or overwrite the model.

// Uses the Sony headset already connected to macOS, else runs the native Bluetooth picker (modal), then
// connects. Call on the main thread; completion runs synchronously on it, after nested run-loop pumping
// while the link opens.
- (void)scanAndConnectWithCompletion:(void (^)(BOOL ok, NSString * _Nullable error))completion;

// Name heuristic for Sony headsets (WH-/WF-/WI-/MDR-/XB/LinkBuds).
+ (BOOL)looksLikeSonyHeadset:(NSString *)name NS_SWIFT_NAME(looksLikeSonyHeadset(_:));
// Address of the first Sony headset currently connected to macOS, or nil.
+ (nullable NSString *)connectedSonyHeadsetAddress NS_SWIFT_NAME(connectedSonyHeadsetAddress());
// YES if the device with this address is connected to macOS (its audio link is up).
+ (BOOL)isDeviceConnectedToMac:(NSString *)address NS_SWIFT_NAME(isDeviceConnectedToMac(_:));
// Opens the control channel to a specific device, without the picker. Call on the main thread; completion
// runs synchronously on the caller's thread, after nested run-loop pumping while the link opens.
- (void)connectToAddress:(NSString *)address
              completion:(void (^)(BOOL ok, NSString * _Nullable error))completion NS_SWIFT_NAME(connect(toAddress:completion:));

- (void)disconnect;

// Pushes the desired ambient/NC state to the device on a background thread; completion on main thread.
- (void)applyMode:(SHCAmbientMode)mode
            level:(NSInteger)level
       focusVoice:(BOOL)focusVoice
       completion:(void (^)(BOOL ok, NSString * _Nullable error))completion;

// On a background thread: v2 devices get the init handshake + NC/ASM channel probe (once per session), then
// NC/ASM, battery, equalizer and DSEE reads - completion on main - then the optional-feature probes -
// completion on main again. v1 devices only get the NC/ASM read (completion called once).
- (void)refreshStatusWithCompletion:(void (^)(void))completion;

// Pushes an equalizer preset (raw EQ_PRESET byte) to the device; completion on main.
- (void)setEqualizerPreset:(NSInteger)preset completion:(void (^)(BOOL ok, NSString * _Nullable error))completion;

// Current custom EQ band value (-10..10) for band 0..4 (5-band layout) or 0..9 (10-band layout).
- (NSInteger)equalizerBandAtIndex:(NSInteger)index;

// Pushes manual/custom EQ (clear bass + 5 bands, each -10..10) to the device - 5-band layout only
// (equalizerWritable).
- (void)setCustomEqualizerBass:(NSInteger)bass bands:(NSArray<NSNumber *> *)bands completion:(void (^)(BOOL ok, NSString * _Nullable error))completion;

// Toggles DSEE / audio upsampling.
- (void)setDsee:(BOOL)enabled completion:(void (^)(BOOL ok, NSString * _Nullable error))completion;

- (void)setAutoPowerOff:(NSInteger)index completion:(void (^)(BOOL ok, NSString * _Nullable error))completion;
- (void)setSpeakToChat:(BOOL)enabled completion:(void (^)(BOOL ok, NSString * _Nullable error))completion;
- (void)setAdaptiveVolume:(BOOL)enabled completion:(void (^)(BOOL ok, NSString * _Nullable error))completion;

// Re-reads the NC/ASM state only (mode, ambient level, focus on voice) so changes made with the headphone's
// own button show up in the app. Called on a timer while connected. Completion on the main thread.
- (void)refreshDynamicWithCompletion:(void (^)(void))completion;

// Re-reads the battery level (v2 devices only). Completion on the main thread.
- (void)refreshBatteryWithCompletion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
