APP := build/MicMute.app
CLT := /Library/Developer/CommandLineTools
CLT_FW := $(CLT)/Library/Developer/Frameworks

# Swift Testing isn't on the default search path with Command Line Tools only.
ifeq ($(shell xcode-select -p 2>/dev/null),$(CLT))
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_FW) -Xlinker -F -Xlinker $(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_FW) -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
endif

# Quit gracefully so MicMute unmutes on the way out; SIGTERM only as a last resort.
define quit_micmute
	@if pgrep -xq MicMute; then \
		osascript -e 'tell application "MicMute" to quit' >/dev/null 2>&1 || true; \
		for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq MicMute || break; sleep 0.3; done; \
		pkill -x MicMute || true; \
	fi
endef

.PHONY: test build app run install clean plugin plugin-test plugin-link

test:
	swift test $(TEST_FLAGS)

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/MicMute $(APP)/Contents/MacOS/MicMute
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

run: app
	$(quit_micmute)
	open $(APP)

install: app
	$(quit_micmute)
	rm -rf /Applications/MicMute.app
	cp -R $(APP) /Applications/MicMute.app
	open /Applications/MicMute.app

clean:
	rm -rf .build build

plugin:
	cd streamdeck && npm run build && npm run validate

plugin-test:
	cd streamdeck && npm test

plugin-link: plugin
	@if [ ! -e "$(HOME)/Library/Application Support/com.elgato.StreamDeck/Plugins/xyz.kayvan.micmute.sdPlugin" ]; then cd streamdeck && npm run link; fi
	cd streamdeck && npm run restart
