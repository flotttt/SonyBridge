#pragma once

#include <optional>
#include <vector>
#include "Constants.h"

// Pure decoders for v2 inquiry replies. `payload` is the frame's <DATA> field, starting with the reply opcode.
namespace ProtocolParsers
{
	struct NcAsmState
	{
		bool enabled;       // NC/ASM effect on
		bool ambient;       // true = Ambient Sound, false = Noise Cancelling
		bool focusOnVoice;
		int level;          // ambient level (meaningful when ambient)
	};

	// Accepts "67|69 17 01 <on> <ambient> <voice> <level>" and the WH-1000XM6 "67|69 19 01 <on> <ambient> <voice>
	// <level> <x> <y>". Returns nullopt when too short, for other opcodes, and for the all-zero body the XM6 sends
	// back on the channel it doesn't use (67 17 00 00 00 00 00).
	std::optional<NcAsmState> parseNcAsmState(const Buffer& payload);

	struct EqualizerState
	{
		unsigned char preset;       // raw preset id (EQ_PRESET values, or ids we don't know yet like 0x30)
		bool hasClearBass;          // 5-band layout only
		int clearBass;              // -10..10 when hasClearBass
		std::vector<int> bands;     // 5 or 10 values in -10..10; empty when the reply carried no band data
	};

	// "57 00 <preset> 06 <bass+10> <b1..b5 +10>" (5 bands + Clear Bass) or "57 00 <preset> 0a <b1..b10 +10>".
	std::optional<EqualizerState> parseEqualizer(const Buffer& payload);
}
