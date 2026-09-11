#include "BluetoothWrapper.h"
#include "CommandSerializer.h"
#include "FakeConnector.h"
#include <cstdio>
#include <memory>
#include <vector>

// Minimal test runner (no framework). Exit code 1 on any failure.
static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { failures++; std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

static Buffer bytes(std::initializer_list<int> values)
{
	Buffer b;
	for (int v : values) b.push_back((char)v);
	return b;
}

static void testNotificationBeforeAck()
{
	auto fakeOwned = std::make_unique<FakeBluetoothConnector>();
	FakeBluetoothConnector* fake = fakeOwned.get();
	BluetoothWrapper wrapper(std::move(fakeOwned));

	// Device sends its own DATA_MDR notification (seq 0) before ACKing (seq 1) the host's frame.
	fake->incomingFrames.push_back(CommandSerializer::packageDataForBt(
		bytes({ 0x69, 0x19, 0x01, 0x01, 0x01, 0x00, 0x0a, 0x00, 0x00 }), DATA_TYPE::DATA_MDR, 0));
	fake->incomingFrames.push_back(CommandSerializer::packageDataForBt({}, DATA_TYPE::ACK, 1));

	wrapper.sendCommand(bytes({ 0x68, 0x17, 0x01, 0x01, 0x01, 0x00, 0x0a }));

	// First sent frame is the command itself (seq 0); the second must be the host's ACK for the
	// notification (ACK type, seq = 1 - notification's seq = 1).
	CHECK(fake->sentFrames.size() >= 2);
	auto firstMsg = unpackSentFrame(fake->sentFrames[0]);
	CHECK(firstMsg.dataType == DATA_TYPE::DATA_MDR && firstMsg.seqNumber == 0);
	auto ackMsg = unpackSentFrame(fake->sentFrames[1]);
	CHECK(ackMsg.dataType == DATA_TYPE::ACK && ackMsg.seqNumber == 1);

	// Next sendCommand must use seq 1 (from the ACK), not repeat/skip because of the notification.
	fake->incomingFrames.push_back(CommandSerializer::packageDataForBt({}, DATA_TYPE::ACK, 0));
	wrapper.sendCommand(bytes({ 0x68, 0x17, 0x01, 0x01, 0x01, 0x00, 0x0b }));

	CHECK(fake->sentFrames.size() >= 3);
	auto secondMsg = unpackSentFrame(fake->sentFrames.back());
	CHECK(secondMsg.dataType == DATA_TYPE::DATA_MDR && secondMsg.seqNumber == 1);
}

static void testPlainAcksToggleSeq()
{
	auto fakeOwned = std::make_unique<FakeBluetoothConnector>();
	FakeBluetoothConnector* fake = fakeOwned.get();
	BluetoothWrapper wrapper(std::move(fakeOwned));

	// Three round trips: seq goes 0 -> 1 -> 0, each answered by an ACK carrying 1 - sent seq.
	fake->incomingFrames.push_back(CommandSerializer::packageDataForBt({}, DATA_TYPE::ACK, 1));
	wrapper.sendCommand(bytes({ 0x67, 0x17 }));
	CHECK(unpackSentFrame(fake->sentFrames[0]).seqNumber == 0);

	fake->incomingFrames.push_back(CommandSerializer::packageDataForBt({}, DATA_TYPE::ACK, 0));
	wrapper.sendCommand(bytes({ 0x67, 0x17 }));
	CHECK(unpackSentFrame(fake->sentFrames[1]).seqNumber == 1);

	fake->incomingFrames.push_back(CommandSerializer::packageDataForBt({}, DATA_TYPE::ACK, 1));
	wrapper.sendCommand(bytes({ 0x67, 0x17 }));
	CHECK(unpackSentFrame(fake->sentFrames[2]).seqNumber == 0);
}

static void testNoAckThrows()
{
	auto fakeOwned = std::make_unique<FakeBluetoothConnector>();
	BluetoothWrapper wrapper(std::move(fakeOwned));

	// No scripted incoming frames at all: recv() throws immediately, sendCommand must not hang.
	bool threw = false;
	try
	{
		wrapper.sendCommand(bytes({ 0x67, 0x17 }));
	}
	catch (const std::exception&)
	{
		threw = true;
	}
	CHECK(threw);
}

static void testDataMdrNo2IsAcked()
{
	auto fakeOwned = std::make_unique<FakeBluetoothConnector>();
	FakeBluetoothConnector* fake = fakeOwned.get();
	BluetoothWrapper wrapper(std::move(fakeOwned));

	// Device sends a DATA_MDR_NO2 frame (seq 0, e.g. a slider echo) before ACKing (seq 1) the host's frame.
	fake->incomingFrames.push_back(CommandSerializer::packageDataForBt(
		bytes({ 0x25, 0x02, 0x01 }), DATA_TYPE::DATA_MDR_NO2, 0));
	fake->incomingFrames.push_back(CommandSerializer::packageDataForBt({}, DATA_TYPE::ACK, 1));

	wrapper.sendCommand(bytes({ 0x68, 0x17, 0x01, 0x01, 0x01, 0x00, 0x0a }));

	// First sent frame is the command itself (seq 0); the second must be the host's ACK for the
	// DATA_MDR_NO2 frame (ACK type, seq = 1 - frame's seq = 1).
	CHECK(fake->sentFrames.size() >= 2);
	auto firstMsg = unpackSentFrame(fake->sentFrames[0]);
	CHECK(firstMsg.dataType == DATA_TYPE::DATA_MDR && firstMsg.seqNumber == 0);
	if (fake->sentFrames.size() >= 2)
	{
		auto ackMsg = unpackSentFrame(fake->sentFrames[1]);
		CHECK(ackMsg.dataType == DATA_TYPE::ACK && ackMsg.seqNumber == 1);
	}

	// Next sendCommand must use seq 1 (from the device's real ACK), not skip because of the NO2 frame.
	fake->incomingFrames.push_back(CommandSerializer::packageDataForBt({}, DATA_TYPE::ACK, 0));
	wrapper.sendCommand(bytes({ 0x68, 0x17, 0x01, 0x01, 0x01, 0x00, 0x0b }));

	CHECK(fake->sentFrames.size() >= 3);
	auto secondMsg = unpackSentFrame(fake->sentFrames.back());
	CHECK(secondMsg.dataType == DATA_TYPE::DATA_MDR && secondMsg.seqNumber == 1);
}

static void testSeqStays1BitAfterTimeout()
{
	auto fakeOwned = std::make_unique<FakeBluetoothConnector>();
	FakeBluetoothConnector* fake = fakeOwned.get();
	BluetoothWrapper wrapper(std::move(fakeOwned));

	// Command #1: seq 0, ACKed with seq 1.
	fake->incomingFrames.push_back(CommandSerializer::packageDataForBt({}, DATA_TYPE::ACK, 1));
	wrapper.sendCommand(bytes({ 0x67, 0x17 }));
	CHECK(unpackSentFrame(fake->sentFrames[0]).seqNumber == 0);

	// Command #2: seq 1, no ACK arrives (recv throws) -> sendCommand must throw.
	bool threw = false;
	try
	{
		wrapper.sendCommand(bytes({ 0x67, 0x17 }));
	}
	catch (const std::exception&)
	{
		threw = true;
	}
	CHECK(threw);
	CHECK(unpackSentFrame(fake->sentFrames[1]).seqNumber == 1);

	// Command #3 must reuse seq 1 (the unanswered frame's seq), never advance to 2.
	fake->incomingFrames.push_back(CommandSerializer::packageDataForBt({}, DATA_TYPE::ACK, 0));
	wrapper.sendCommand(bytes({ 0x67, 0x17 }));
	CHECK(unpackSentFrame(fake->sentFrames[2]).seqNumber == 1);
}

static void testSendCommandAndReadResponseSeqStays1Bit()
{
	auto fakeOwned = std::make_unique<FakeBluetoothConnector>();
	FakeBluetoothConnector* fake = fakeOwned.get();
	BluetoothWrapper wrapper(std::move(fakeOwned));

	// No scripted incoming frames: the response never arrives, sendCommandAndReadResponse throws.
	bool threw = false;
	try
	{
		wrapper.sendCommandAndReadResponse(bytes({ 0x67, 0x17 }), 0x69);
	}
	catch (const std::exception&)
	{
		threw = true;
	}
	CHECK(threw);
	CHECK(unpackSentFrame(fake->sentFrames[0]).seqNumber == 0);

	// Next command must reuse seq 0 (the unanswered frame's seq), not advance to 1.
	fake->incomingFrames.push_back(CommandSerializer::packageDataForBt({}, DATA_TYPE::ACK, 1));
	wrapper.sendCommand(bytes({ 0x67, 0x17 }));
	CHECK(unpackSentFrame(fake->sentFrames[1]).seqNumber == 0);
}

int main()
{
	testNotificationBeforeAck();
	testPlainAcksToggleSeq();
	testNoAckThrows();
	testDataMdrNo2IsAcked();
	testSeqStays1BitAfterTimeout();
	testSendCommandAndReadResponseSeqStays1Bit();

	if (failures) { std::printf("BluetoothWrapperTests: %d failure(s)\n", failures); return 1; }
	std::printf("BluetoothWrapperTests: all passed\n");
	return 0;
}
