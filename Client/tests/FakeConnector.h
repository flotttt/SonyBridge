#pragma once

#include "BluetoothWrapper.h"
#include "CommandSerializer.h"
#include "IBluetoothConnector.h"
#include "Exceptions.h"
#include <algorithm>
#include <deque>
#include <stdexcept>
#include <vector>

// Records every frame handed to send() and hands back scripted incoming frames one whole frame per
// recv() call. When the script is exhausted, recv() throws like the real macOS connector does after
// its 2.5s timeout. Shared by BluetoothWrapperTests.cpp and HeadphonesTests.cpp.
class FakeBluetoothConnector : public IBluetoothConnector
{
public:
	std::vector<Buffer> sentFrames;
	std::deque<Buffer> incomingFrames;

	int send(char* buf, size_t length) noexcept(false) override
	{
		this->sentFrames.emplace_back(buf, buf + length);
		return static_cast<int>(length);
	}

	int recv(char* buf, size_t length) noexcept(false) override
	{
		if (this->incomingFrames.empty())
		{
			throw RecoverableException("recv timed out", false);
		}
		auto frame = this->incomingFrames.front();
		this->incomingFrames.pop_front();
		if (frame.size() > length)
		{
			throw std::runtime_error("scripted frame too large for buffer");
		}
		std::copy(frame.begin(), frame.end(), buf);
		return static_cast<int>(frame.size());
	}

	void connect(const std::string&) noexcept(false) override {}
	void disconnect() noexcept override {}
	bool isConnected() noexcept override { return true; }
	std::vector<BluetoothDevice> getConnectedDevices() override { return {}; }
	SonyProtocolVersion getProtocolVersion() noexcept override { return SonyProtocolVersion::V1; }
};

// Decodes a frame previously recorded by FakeBluetoothConnector::send (includes START_MARKER/END_MARKER).
inline CommandSerializer::Message unpackSentFrame(const Buffer& frame)
{
	return CommandSerializer::unpackBtMessage(Buffer(frame.begin() + 1, frame.end() - 1));
}
