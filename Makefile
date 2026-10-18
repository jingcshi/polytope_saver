export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

SWIFT_FLAGS :=
SAVER := build/Polychora.saver
APP := build/Polychora.app
APPEX := $(APP)/Contents/PlugIns/Polychora.appex
PREVIEW := .build/release/PolychoraPreview
LEGACY_DIR := $(HOME)/Library/Screen Savers
# pkd rejects third-party appexes whose host app lives anywhere but /Applications
# ("plug-ins outside containing apps must be protected by SIP"). Writing here needs admin.
APP_DIR := /Applications
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: all app saver shaders test preview thumbnail install uninstall install-legacy uninstall-legacy clean

all: app

test:
	swift test $(SWIFT_FLAGS)

shaders: build/Polychora.metallib

build/Polychora.metallib: Shaders/Polychora.metal
	@mkdir -p build
	xcrun metal -c $< -o build/Polychora.air
	xcrun metallib build/Polychora.air -o $@

# ExtensionKit screensaver (.appex) inside a stub host app. This is the default.
app: shaders
	swift build $(SWIFT_FLAGS) -c release --product PolychoraAppex
	swift build $(SWIFT_FLAGS) -c release --product PolychoraHost
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APPEX)/Contents/MacOS $(APPEX)/Contents/Resources
	cp Resources/Host/Info.plist $(APP)/Contents/
	cp .build/release/PolychoraHost $(APP)/Contents/MacOS/
	cp Resources/Appex/Info.plist $(APPEX)/Contents/
	cp .build/release/PolychoraAppex $(APPEX)/Contents/MacOS/
	cp Shaders/Polychora.metal build/Polychora.metallib $(APPEX)/Contents/Resources/
	cp Resources/Appex/thumbnail*.png $(APPEX)/Contents/Resources/ 2>/dev/null || true
	codesign --force --sign - --entitlements Resources/Appex/Appex.entitlements $(APPEX)
	codesign --force --sign - $(APP)

# Legacy .saver bundle hosted by legacyScreenSaver (kept as a fallback).
saver: shaders
	swift build $(SWIFT_FLAGS) -c release --product PolychoraSaver
	rm -rf $(SAVER)
	mkdir -p $(SAVER)/Contents/MacOS $(SAVER)/Contents/Resources
	cp Resources/Info.plist $(SAVER)/Contents/
	cp .build/release/libPolychoraSaver.dylib $(SAVER)/Contents/MacOS/Polychora
	cp Shaders/Polychora.metal build/Polychora.metallib $(SAVER)/Contents/Resources/
	cp Resources/thumbnail*.png $(SAVER)/Contents/Resources/ 2>/dev/null || true
	codesign --force --sign - $(SAVER)

preview:
	swift run $(SWIFT_FLAGS) -c release PolychoraPreview

# Needs GPU access (run outside any sandbox).
thumbnail:
	swift build $(SWIFT_FLAGS) -c release --product PolychoraPreview
	$(PREVIEW) --snapshot Resources/thumbnail.png --kind 120 --stereo 1 --size 480x312
	$(PREVIEW) --snapshot Resources/thumbnail@2x.png --kind 120 --stereo 1 --size 960x624
	$(PREVIEW) --snapshot Resources/Appex/thumbnail.png --kind 120 --stereo 1 --size 107x65
	$(PREVIEW) --snapshot Resources/Appex/thumbnail@2x.png --kind 120 --stereo 1 --size 214x130

install: app uninstall-legacy
	-pluginkit -r "$(APP_DIR)/Polychora.app/Contents/PlugIns/Polychora.appex" 2>/dev/null
	rm -rf "$(APP_DIR)/Polychora.app"
	mkdir -p "$(APP_DIR)"
	cp -R $(APP) "$(APP_DIR)/"
	-$(LSREGISTER) -u $(APP)
	$(LSREGISTER) -f "$(APP_DIR)/Polychora.app"
	open "$(APP_DIR)/Polychora.app" --args --register-only
	sleep 2
	pluginkit -a "$(APP_DIR)/Polychora.app/Contents/PlugIns/Polychora.appex"
	sleep 2
	@pluginkit -m -v -p com.apple.screensaver | grep -i polychora || echo "warning: pluginkit does not list Polychora"
	@echo "Installed. Launch /Applications/Polychora.app to make it the screensaver on all displays."

uninstall:
	-pluginkit -r "$(APP_DIR)/Polychora.app/Contents/PlugIns/Polychora.appex" 2>/dev/null
	rm -rf "$(APP_DIR)/Polychora.app"

install-legacy: saver uninstall
	rm -rf "$(LEGACY_DIR)/Polychora.saver"
	mkdir -p "$(LEGACY_DIR)"
	cp -R $(SAVER) "$(LEGACY_DIR)/"
	-killall legacyScreenSaver 2>/dev/null
	@echo "Installed. Pick 'Polychora' under System Settings → Wallpaper → Screen Saver → Other."

uninstall-legacy:
	rm -rf "$(LEGACY_DIR)/Polychora.saver"
	-killall legacyScreenSaver 2>/dev/null

clean:
	rm -rf build .build
