#include "Headphones.h"
#include "BluetoothWrapper.h"
#include "CommandSerializer.h"
#include "Constants.h"
#include "FakeConnector.h"
#include <cstdio>
#include <memory>

// Minimal test runner (no framework). Exit code 1 on any failure.
static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { failures++; std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

static Buffer bytes(std::initializer_list<int> values)
{
	Buffer b;
	for (int v : values) b.push_back((char)v);
	return b;
}

// Scripts a single DATA_MDR reply so sendCommandAndReadResponse's read loop matches it directly -
// BluetoothWrapper ACKs DATA_MDR frames itself, so no separate scripted ACK frame is needed.
static void scriptResponse(FakeBluetoothConnector& fake, std::initializer_list<int> payload)
{
	fake.incomingFrames.push_back(CommandSerializer::packageDataForBt(bytes(payload), DATA_TYPE::DATA_MDR, 0));
}

// A connector that answers only the specific (opcode, subtype) requests it's told to, and times out (throws)
// for everything else - including requests it was never asked about. The plain FIFO FakeBluetoothConnector
// can't model "this one inquiry never answers, but a later different inquiry does" because it hands back
// whatever's queued regardless of which request is asking; a device really just never replies to an
// unsupported inquiry rather than replying out of order to an unrelated one.
class SelectiveFakeConnector : public FakeBluetoothConnector
{
public:
	void scriptReplyTo(unsigned char opcode, unsigned char subtype, std::initializer_list<int> payload)
	{
		this->replies.push_back({ { opcode, subtype }, bytes(payload) });
	}

	int recv(char* buf, size_t length) noexcept(false) override
	{
		if (this->sentFrames.empty()) throw RecoverableException("recv timed out", false);
		auto lastSent = unpackSentFrame(this->sentFrames.back());
		for (const auto& entry : this->replies)
		{
			if (lastSent.payload.size() >= 2
				&& (unsigned char)lastSent.payload[0] == entry.first.first
				&& (unsigned char)lastSent.payload[1] == entry.first.second)
			{
				auto frame = CommandSerializer::packageDataForBt(entry.second, DATA_TYPE::DATA_MDR, 0);
				if (frame.size() > length) throw std::runtime_error("scripted frame too large for buffer");
				std::copy(frame.begin(), frame.end(), buf);
				return static_cast<int>(frame.size());
			}
		}
		throw RecoverableException("recv timed out", false);
	}

private:
	std::vector<std::pair<std::pair<unsigned char, unsigned char>, Buffer>> replies;
};

// Cases (1) + (2): a real WH-1000XM6 answers the single-battery inquiry once (55%, not charging), then a
// later poll's 22 00 times out (no scripted reply). The transient timeout must NOT fall back to probing
// the TWS commands (22 09 / 22 0a) - that flips hasDualBattery() to true forever, which is the header's
// "G 0 % D 9 % Boîtier 0 %" bug on a single-battery device.
static void testTransientBatteryTimeoutKeepsSingleBattery()
{
	auto fakeOwned = std::make_unique<FakeBluetoothConnector>();
	FakeBluetoothConnector* fake = fakeOwned.get();
	BluetoothWrapper wrapper(std::move(fakeOwned));
	Headphones phones(wrapper);

	// (1) 22 00 answered -> 23 00 37 00 (level 55, not charging).
	scriptResponse(*fake, { 0x23, 0x00, 0x37, 0x00 });
	phones.requestBattery();
	CHECK(phones.getBatteryLevel() == 55);
	CHECK(phones.hasDualBattery() == false);

	// (2) 22 00 now times out (no scripted reply queued) - must not probe 22 09 / 22 0a, and the last
	// known values must be kept.
	fake->sentFrames.clear();
	phones.requestBattery();

	for (const auto& frame : fake->sentFrames)
	{
		auto msg = unpackSentFrame(frame);
		bool isBatteryGet = msg.payload.size() >= 2 && (unsigned char)msg.payload[0] == V2Command::BATTERY_GET;
		bool isTwsProbe = isBatteryGet
			&& ((unsigned char)msg.payload[1] == 0x09 || (unsigned char)msg.payload[1] == 0x0a);
		CHECK(!isTwsProbe);
	}
	CHECK(phones.hasDualBattery() == false);
	CHECK(phones.getBatteryLevel() == 55);
}

// Case (3): a TWS device whose 22 00 never answers must still pick up its dual battery from 22 09 - the
// fix must not break the existing TWS probing path for devices that have no single-battery inquiry at all.
static void testTwsDeviceWithNoSingleBatteryStillProbes()
{
	auto fakeOwned = std::make_unique<SelectiveFakeConnector>();
	SelectiveFakeConnector* fake = fakeOwned.get();
	BluetoothWrapper wrapper(std::move(fakeOwned));
	Headphones phones(wrapper);

	// 22 00 has no scripted reply at all (times out); only 22 09 answers, L=50% (not charging),
	// R=50% (not charging); 22 0a (case) has no scripted reply either.
	fake->scriptReplyTo(V2Command::BATTERY_GET, 0x09, { 0x23, 0x09, 0x32, 0x00, 0x32, 0x00 });
	phones.requestBattery();

	CHECK(phones.hasDualBattery() == true);
}

int main()
{
	testTransientBatteryTimeoutKeepsSingleBattery();
	testTwsDeviceWithNoSingleBatteryStillProbes();

	if (failures) { std::printf("HeadphonesTests: %d failure(s)\n", failures); return 1; }
	std::printf("HeadphonesTests: all passed\n");
	return 0;
}
