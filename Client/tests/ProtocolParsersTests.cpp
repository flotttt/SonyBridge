#include "ProtocolParsers.h"
#include "CommandSerializer.h"
#include <cstdio>
#include <initializer_list>

// Minimal test runner (no framework). Exit code 1 on any failure.
static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { failures++; std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

static Buffer bytes(std::initializer_list<int> values)
{
	Buffer b;
	for (int v : values) b.push_back((char)v);
	return b;
}

int main()
{
	using namespace ProtocolParsers;

	// --- NC/ASM state ---
	// WH-1000XM6 answer to the legacy 0x17 inquiry: all zeros = "not this channel".
	CHECK(!parseNcAsmState(bytes({ 0x67, 0x17, 0x00, 0x00, 0x00, 0x00, 0x00 })).has_value());
	// WH-1000XM6 notify on 0x19: Ambient Sound on, level 10, no voice focus.
	{
		auto s = parseNcAsmState(bytes({ 0x69, 0x19, 0x01, 0x01, 0x01, 0x00, 0x0a, 0x00, 0x00 }));
		CHECK(s && s->enabled && s->ambient && !s->focusOnVoice && s->level == 10);
	}
	// WH-1000XM6 reply on 0x19: Noise Cancelling (ambient byte = 0).
	{
		auto s = parseNcAsmState(bytes({ 0x67, 0x19, 0x01, 0x01, 0x00, 0x00, 0x0a, 0x00, 0x00 }));
		CHECK(s && s->enabled && !s->ambient);
	}
	// Legacy 0x17 layout (WH-CH720N): effect off.
	{
		auto s = parseNcAsmState(bytes({ 0x67, 0x17, 0x01, 0x00, 0x00, 0x00, 0x01 }));
		CHECK(s && !s->enabled);
	}
	CHECK(!parseNcAsmState(bytes({ 0x67, 0x17, 0x01 })).has_value());                          // too short
	CHECK(!parseNcAsmState(bytes({ 0x57, 0x17, 0x01, 0x01, 0x01, 0x00, 0x0a })).has_value());   // wrong opcode

	// --- Equalizer ---
	// WH-1000XM6: unknown preset 0x30, 10 bands (offset +10 hypothesis, spec §7).
	{
		auto e = parseEqualizer(bytes({ 0x57, 0x00, 0x30, 0x0a, 0x0a, 0x0a, 0x05, 0x05, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06 }));
		CHECK(e && e->preset == 0x30 && !e->hasClearBass && e->bands.size() == 10);
		CHECK(e && e->bands[0] == 0 && e->bands[2] == -5 && e->bands[9] == -4);
	}
	// 5 bands + Clear Bass (WH-CH720N): Manual, bass +3, bands -2..+2.
	{
		auto e = parseEqualizer(bytes({ 0x57, 0x00, 0xa0, 0x06, 13, 8, 9, 10, 11, 12 }));
		CHECK(e && e->preset == 0xa0 && e->hasClearBass && e->clearBass == 3);
		CHECK(e && e->bands == std::vector<int>({ -2, -1, 0, 1, 2 }));
	}
	// Preset only, no band data.
	{
		auto e = parseEqualizer(bytes({ 0x57, 0x00, 0x16 }));
		CHECK(e && e->preset == 0x16 && e->bands.empty());
	}
	CHECK(!parseEqualizer(bytes({ 0x23, 0x00, 0x44, 0x00 })).has_value());                     // battery reply

	// --- Framing ---
	// Round trip, with a payload byte (0x3c = END_MARKER) that must be escaped.
	{
		Buffer payload = bytes({ 0x68, 0x17, 0x01, 0x01, 0x01, 0x00, 0x3c });
		auto frame = CommandSerializer::packageDataForBt(payload, DATA_TYPE::DATA_MDR, 1);
		CHECK(frame.front() == START_MARKER && frame.back() == END_MARKER);
		auto msg = CommandSerializer::unpackBtMessage(Buffer(frame.begin() + 1, frame.end() - 1));
		CHECK(msg.dataType == DATA_TYPE::DATA_MDR && msg.seqNumber == 1 && msg.payload == payload);
	}
	// Real WH-1000XM6 battery frame (68 %), between the 3e/3c markers.
	{
		auto msg = CommandSerializer::unpackBtMessage(bytes({ 0x0c, 0x00, 0x00, 0x00, 0x00, 0x04, 0x23, 0x00, 0x44, 0x00, 0x77 }));
		CHECK(msg.payload == bytes({ 0x23, 0x00, 0x44, 0x00 }));
	}

	if (failures) { std::printf("ProtocolParsersTests: %d failure(s)\n", failures); return 1; }
	std::printf("ProtocolParsersTests: all passed\n");
	return 0;
}
