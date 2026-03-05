APP_NAME := Vox
APP_PATH := /Applications/$(APP_NAME).app
BINARY := $(APP_PATH)/Contents/MacOS/$(APP_NAME)
BUILD_BINARY := .build/debug/SttTool
SIGN_IDENTITY := Vox

.PHONY: build install run clean

build:
	swift build

install: build
	@killall $(APP_NAME) 2>/dev/null || true
	@sleep 0.5
	@cp -f $(BUILD_BINARY) $(BINARY)
	@codesign --force --sign "$(SIGN_IDENTITY)" $(BINARY)
	@echo "Installed and signed as '$(SIGN_IDENTITY)'"
	@open $(APP_PATH)

run: build
	@killall $(APP_NAME) 2>/dev/null || true
	@sleep 0.5
	@cp -f $(BUILD_BINARY) $(BINARY)
	@codesign --force --sign "$(SIGN_IDENTITY)" $(BINARY)
	@open $(APP_PATH)

clean:
	swift package clean
