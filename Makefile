APP := build/MicMute.app
CLT := /Library/Developer/CommandLineTools
CLT_FW := $(CLT)/Library/Developer/Frameworks

# Swift Testing isn't on the default search path with Command Line Tools only.
ifeq ($(shell xcode-select -p 2>/dev/null),$(CLT))
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_FW) -Xlinker -F -Xlinker $(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_FW) -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
endif

.PHONY: test build app run install clean

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
	-pkill -x MicMute
	open $(APP)

install: app
	-pkill -x MicMute
	rm -rf /Applications/MicMute.app
	cp -R $(APP) /Applications/MicMute.app
	open /Applications/MicMute.app

clean:
	rm -rf .build build
