export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

SWIFT_FLAGS := --disable-sandbox
SAVER := build/Polychora.saver
PREVIEW := .build/release/PolychoraPreview
INSTALL_DIR := $(HOME)/Library/Screen Savers

.PHONY: all saver shaders test preview thumbnail install uninstall clean

all: saver

test:
	swift test $(SWIFT_FLAGS)

shaders: build/Polychora.metallib

build/Polychora.metallib: Shaders/Polychora.metal
	@mkdir -p build
	xcrun metal -c $< -o build/Polychora.air
	xcrun metallib build/Polychora.air -o $@

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

install: saver
	rm -rf "$(INSTALL_DIR)/Polychora.saver"
	mkdir -p "$(INSTALL_DIR)"
	cp -R $(SAVER) "$(INSTALL_DIR)/"
	-killall legacyScreenSaver 2>/dev/null
	@echo "Installed. Pick 'Polychora' under System Settings → Wallpaper → Screen Saver → Other."

uninstall:
	rm -rf "$(INSTALL_DIR)/Polychora.saver"
	-killall legacyScreenSaver 2>/dev/null

clean:
	rm -rf build .build
