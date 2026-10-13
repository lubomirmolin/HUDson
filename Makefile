APP := build/HUDson.app
# A stable signing identity keeps the Accessibility grant alive across rebuilds. Uses your first
# Apple Development certificate, or ad-hoc signing (re-grant Accessibility after each build).
IDENTITY ?= $(or $(shell security find-identity -v -p codesigning | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"'),-)

.PHONY: app icon install release clean

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

# Public builds are ad-hoc signed: a developer certificate would embed its name and team in the zip.
release:
	$(MAKE) app IDENTITY=-
	# Debug symbols carry absolute build paths (home folder, username).
	strip -S -x $(APP)/Contents/MacOS/HUDson
	codesign --force --options runtime --sign - $(APP)
	rm -f HUDson.zip
	ditto -c -k --norsrc --noextattr --keepParent $(APP) HUDson.zip

clean:
	rm -rf .build build
