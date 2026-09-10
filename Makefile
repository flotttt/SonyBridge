# SonyBridge — build without Xcode. See scripts/build.sh for the knobs.
DEBUG ?= 0

.PHONY: all build run test release clean

all: build

build:
	DEBUG_PROTOCOL=$(DEBUG) ./scripts/build.sh

run: build
	-pkill -x SonyBridge
	open --stdout build/app.log --stderr build/app.log build/SonyBridge.app

test:
	./scripts/test.sh

release:
	CONFIG=release ARCHS="arm64 x86_64" ./scripts/build.sh
	cd build && rm -f SonyBridge.zip && ditto -c -k --keepParent SonyBridge.app SonyBridge.zip

clean:
	rm -rf build
