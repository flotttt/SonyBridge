#include "ProtocolParsers.h"

#include <algorithm>

namespace ProtocolParsers
{
	std::optional<NcAsmState> parseNcAsmState(const Buffer& payload)
	{
		if (payload.size() < 7) return std::nullopt;
		auto opcode = (unsigned char)payload[0];
		auto type = (unsigned char)payload[1];
		if ((opcode != 0x67 && opcode != 0x69) || (type != 0x17 && type != 0x19)) return std::nullopt;
		if (std::all_of(payload.begin() + 2, payload.end(), [](char b) { return b == 0; })) return std::nullopt;

		NcAsmState state;
		state.enabled = payload[3] != 0;
		state.ambient = payload[4] != 0;
		state.focusOnVoice = payload[5] != 0;
		state.level = (unsigned char)payload[6];
		return state;
	}

	std::optional<EqualizerState> parseEqualizer(const Buffer& payload)
	{
		if (payload.size() < 3 || (unsigned char)payload[0] != 0x57) return std::nullopt;

		EqualizerState state{ (unsigned char)payload[2], false, 0, {} };
		if (payload.size() < 4) return state;
		size_t count = (unsigned char)payload[3];
		if (payload.size() < 4 + count) return state;

		auto value = [&](size_t i) { return (int)(unsigned char)payload[4 + i] - 10; };
		if (count == 6)
		{
			state.hasClearBass = true;
			state.clearBass = value(0);
			for (size_t i = 1; i < 6; i++) state.bands.push_back(value(i));
		}
		else if (count == 10)
		{
			for (size_t i = 0; i < 10; i++) state.bands.push_back(value(i));
		}
		return state;
	}
}
