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

.PHONY: test build app run install clean icon plugin plugin-test plugin-link

test:
	swift test $(TEST_FLAGS)

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/MicMute $(APP)/Contents/MacOS/MicMute
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
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

# Regenerate the app icon (Resources/AppIcon.icns) and the Stream Deck plugin icon
# (plugin.png 256 px + @2x) from Resources/AppIcon.png (1024 px or larger).
icon:
	rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
	for size in 16 32 128 256 512; do \
		sips -z $$size $$size Resources/AppIcon.png --out build/AppIcon.iconset/icon_$${size}x$${size}.png >/dev/null; \
		sips -z $$((size * 2)) $$((size * 2)) Resources/AppIcon.png --out build/AppIcon.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
	sips -z 256 256 Resources/AppIcon.png --out streamdeck/xyz.kayvan.micmute.sdPlugin/imgs/plugin.png >/dev/null
	sips -z 512 512 Resources/AppIcon.png --out streamdeck/xyz.kayvan.micmute.sdPlugin/imgs/plugin@2x.png >/dev/null
