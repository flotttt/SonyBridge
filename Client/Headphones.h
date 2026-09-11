#include "BluetoothWrapper.h"
#include "Constants.h"

#include <atomic>
#include <mutex>

template <class T>
struct Property {
	T current;
	T desired;

	void fulfill();
	bool isFulfilled();
};

class Headphones {
public:
	Headphones(BluetoothWrapper& conn);

	void setAmbientSoundControl(bool val);
	bool getAmbientSoundControl();

	bool isFocusOnVoiceAvailable();
	void setFocusOnVoice(bool val);
	bool getFocusOnVoice();

	bool isSetAsmLevelAvailable();
	void setAsmLevel(int val);
	int getAsmLevel();

	void setSurroundPosition(SOUND_POSITION_PRESET val);
	SOUND_POSITION_PRESET getSurroundPosition();

	void setVptType(int val);
	int getVptType();

	// SAFETY: every v2-only inquiry/setter below (init, battery, equalizer, DSEE, NC/ASM probe, capability
	// probes and their setters) returns WITHOUT sending anything when the live link isn't v2 - opcode 0x22
	// (BATTERY_GET on v2) is POWER_OFF on v1. This guards against a stale session's queued work reaching a
	// v1 headset that got connected on the same BluetoothWrapper right after.

	// Handshake the device expects before it answers inquiry (GET) commands on the v2 protocol.
	void initDevice();
	// True once initDevice() got its reply. Per object, i.e. per connection session.
	bool isInitialized();

	// Battery (v2 inquiry). getBatteryLevel() returns -1 until requestBattery() succeeds.
	// For TWS earbuds requestBattery() also fills the per-earbud + case levels (hasDualBattery()).
	void requestBattery();
	int getBatteryLevel();
	bool isBatteryCharging();
	bool hasDualBattery();
	int getBatteryLeft();   // -1 if n/a
	int getBatteryRight();
	int getBatteryCase();

	// Equalizer (v2). requestEqualizer() reads current state; setEqualizerPreset() pushes a preset immediately.
	void requestEqualizer();
	EQ_PRESET getEqualizerPreset();
	void setEqualizerPreset(EQ_PRESET preset);
	// Custom (manual) EQ: 5 band values + clear bass, each in [-10, 10]. Selects the MANUAL preset.
	void setEqualizerCustom(int clearBass, const std::vector<int>& bands);
	int getClearBass();
	int getEqualizerBand(int index); // 0..4 (5-band layout) or 0..9 (10-band layout)
	int getEqualizerBandCount();   // 0 until read, then 5 (+ Clear Bass) or 10
	bool equalizerHasClearBass();

	// DSEE / audio upsampling (v2).
	void requestDsee();
	bool hasDsee(); // true once the device answered requestDsee()
	bool getDsee();
	void setDsee(bool enabled);

	// Reads the device's current ambient/NC state into the *current* properties (for live polling so
	// changes made with the headphone's own button are reflected in the app).
	void requestAmbientState();

	// Picks the NC/ASM inquiry channel: 0x19 when the device answers it (WH-1000XM6), else the legacy 0x17.
	void probeNcAsmInquiryType();

	// Optional features. probeCapabilities() sends each GET on connect; a feature is "supported" only if
	// the device answers (otherwise we must never send its SET - see the WH-1000XM4 power-off incident).
	void probeCapabilities();

	bool hasAutoPowerOff();
	int getAutoPowerOff();               // index into the option list (0=Off,1=5m,2=30m,3=1h,4=3h,5=when taken off)
	void setAutoPowerOff(int index);

	bool hasFirmware();
	std::string getFirmware();
	bool hasCodec();
	std::string getCodec();

	bool hasSpeakToChat();
	bool getSpeakToChat();
	void setSpeakToChat(bool enabled);

	bool hasAdaptiveVolume();
	bool getAdaptiveVolume();
	void setAdaptiveVolume(bool enabled);

	bool isChanged();
	void setChanges();
private:
	// Checked on every v2-only call (not cached): the wrapper's link can change under a long-lived object.
	bool isV2();

	std::atomic<bool> _initialized{ false };

	Property<bool> _ambientSoundControl = { 0 };
	Property<bool> _focusOnVoice = { 0 };
	Property<int> _asmLevel = { 0 };
	Property<SOUND_POSITION_PRESET> _surroundPosition = { SOUND_POSITION_PRESET::OUT_OF_RANGE, SOUND_POSITION_PRESET::OFF };
	Property<int> _vptType = { 0 };

	int _batteryLevel = -1;
	bool _batteryCharging = false;
	bool _hasDualBattery = false;
	// Set once GET 22 00 succeeds. Guards requestBattery() against a later transient timeout on 22 00
	// falling through to the TWS probes (22 09/22 0a), which would wrongly flip _hasDualBattery to true
	// and never reset it - see requestBattery().
	bool _singleBatteryKnown = false;
	int _batteryLeft = -1;
	int _batteryRight = -1;
	int _batteryCase = -1;
	EQ_PRESET _eqPreset = EQ_PRESET::OFF;
	std::vector<int> _eqBands;              // empty until the first read; 5 or 10 values
	bool _eqHasClearBass = false;
	unsigned char _ncAsmInquiryType = 0x17; // 0x19 on the WH-1000XM6, see probeNcAsmInquiryType()
	int _eqClearBass = 0;
	bool _dsee = false;
	bool _hasDsee = false;

	bool _hasAutoPowerOff = false; int _autoPowerOff = 0;
	bool _hasFirmware = false; std::string _firmware;
	bool _hasCodec = false; std::string _codec;
	bool _hasSpeakToChat = false; bool _speakToChat = false;
	bool _hasAdaptiveVolume = false; bool _adaptiveVolume = false;

	std::mutex _propertyMtx;

	BluetoothWrapper& _conn;
};

template<class T>
inline void Property<T>::fulfill()
{
	this->current = this->desired;
}

template<class T>
inline bool Property<T>::isFulfilled()
{
	return this->desired == this->current;
}
