DYLIB_NAME := FnMacCrashFix
SRC        := src/fix.c src/fishhook.c

# ── Toolchain ────────────────────────────────────────────────────
CC         := $(shell xcrun -f clang)
IOS_SDK    := $(shell xcrun --show-sdk-path --sdk iphoneos)
MIN_IOS    := 26.0
LIPO       := $(shell xcrun -f lipo)

# ── Common flags ─────────────────────────────────────────────────
COMMON := -isysroot $(IOS_SDK) \
          -miphoneos-version-min=$(MIN_IOS) \
          -dynamiclib \
          -O2 -Wall -Wextra \
          -install_name @rpath/$(DYLIB_NAME).dylib

# ── Targets ──────────────────────────────────────────────────────
BUILD_DIR := build

.PHONY: all clean

all: $(BUILD_DIR)/$(DYLIB_NAME).dylib
	@echo "✓ Built $(BUILD_DIR)/$(DYLIB_NAME).dylib"
	@file $(BUILD_DIR)/$(DYLIB_NAME).dylib

$(BUILD_DIR)/$(DYLIB_NAME).dylib: $(BUILD_DIR)/arm64.dylib $(BUILD_DIR)/arm64e.dylib
	$(LIPO) -create $^ -output $@
	codesign -f -s - $@

$(BUILD_DIR)/arm64.dylib: $(SRC) | $(BUILD_DIR)
	$(CC) -arch arm64 $(COMMON) -o $@ $(SRC)

$(BUILD_DIR)/arm64e.dylib: $(SRC) | $(BUILD_DIR)
	$(CC) -arch arm64e $(COMMON) -o $@ $(SRC)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR)
