SDK     := $(shell xcrun --show-sdk-path)
ifeq ($(SDK),)
$(error Failed to find SDK path. Ensure Xcode command-line tools are installed.)
endif

CC      := clang
COMMON  := -mmacosx-version-min=13.0 -isysroot $(SDK) -fobjc-arc -Wall -Werror -O2 -fstack-protector-strong

BUILD   := build
DYLIB   := $(BUILD)/SpacePayload.dylib
LOADER  := $(BUILD)/SpaceMoverLoader

all: $(BUILD) $(DYLIB) $(LOADER)

$(BUILD):
	mkdir -p $@

$(DYLIB): payload.m common.h
	$(CC) -arch arm64 $(COMMON) -dynamiclib -framework Foundation \
	    -o $@ payload.m

$(LOADER): loader.m
	$(CC) -arch arm64 $(COMMON) -framework Foundation -framework AppKit \
	    -o $@ loader.m

clean:
	rm -rf $(BUILD)

.PHONY: all clean
