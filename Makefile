APP := build/HUDson.app
# A stable signing identity keeps the Accessibility grant alive across rebuilds. Uses your first
# Apple Development certificate, or ad-hoc signing (re-grant Accessibility after each build).
IDENTITY ?= $(or $(shell security find-identity -v -p codesigning | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"'),-)

.PHONY: app icon install clean

app: icon
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/HUDson $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	cp Resources/AppIcon.svg Resources/StatusIcon.svg $(APP)/Contents/Resources/
	codesign --force --options runtime --sign "$(IDENTITY)" $(APP)

icon:
	swift scripts/render-icon.swift build
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

install: app
	-pkill -x HUDson
	rm -rf /Applications/HUDson.app
	cp -R $(APP) /Applications/
	open /Applications/HUDson.app

clean:
	rm -rf .build build
