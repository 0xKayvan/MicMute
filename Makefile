CLT := /Library/Developer/CommandLineTools
CLT_FW := $(CLT)/Library/Developer/Frameworks

# Swift Testing isn't on the default search path with Command Line Tools only.
ifeq ($(shell xcode-select -p 2>/dev/null),$(CLT))
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_FW) -Xlinker -F -Xlinker $(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_FW)
endif

.PHONY: test

test:
	swift test $(TEST_FLAGS)
