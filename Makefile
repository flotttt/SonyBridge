# SonyBridge — build without Xcode. See scripts/build.sh for the knobs.
DEBUG ?= 0

.PHONY: all build run test release clean

all: build

build:
	DEBUG_PROTOCOL=$(DEBUG) ./scripts/build.sh

LOG_FILE := $(HOME)/Library/Logs/SonyBridge/app.log

run: build
	-pkill -x SonyBridge; while pgrep -x SonyBridge >/dev/null; do sleep 0.2; done
	@mkdir -p "$(dir $(LOG_FILE))"
	@ln -sfn "$(LOG_FILE)" "$(CURDIR)/build/app.log"
	@echo "=== SonyBridge session $$(date '+%Y-%m-%d %H:%M:%S') ===" >> "$(LOG_FILE)"
	open "$(CURDIR)/build/SonyBridge.app" --args -SonyBridgeLogFile "$(LOG_FILE)"

test:
	./scripts/test.sh

release:
	CONFIG=release ARCHS="arm64 x86_64" ./scripts/build.sh
	cd build && rm -f SonyBridge.zip && ditto -c -k --keepParent SonyBridge.app SonyBridge.zip

clean:
	rm -rf build
