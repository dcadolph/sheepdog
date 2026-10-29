APP := .build/Sheepdog.app
DEMO_APP := .build/demo/Sheepdog.app
SIGN_ID ?= -
ENTITLEMENTS := Sheepdog.entitlements
# A real identity gets a secure timestamp, which notarization requires. Ad-hoc builds skip it so local
# and CI mirror builds never need the network.
TIMESTAMP := $(if $(filter -,$(SIGN_ID)),,--timestamp)
PLIST := $(APP)/Contents/Info.plist
SHEEPDOG_MICROSOFT_CLIENT_ID ?=
SHEEPDOG_GOOGLE_CLIENT_ID ?=
SHEEPDOG_GOOGLE_CLIENT_SECRET ?=
SHEEPDOG_SUPPORT_URL ?=
ARCHS ?=
ARCH_FLAGS := $(foreach arch,$(ARCHS),--arch $(arch))
ZIP ?= .build/Sheepdog.zip
DMG ?= .build/Sheepdog.dmg
DMGBUILD ?= dmgbuild

ICONSET := .build/AppIcon.iconset
ICNS := .build/AppIcon.icns
RUNTIME_ART := art/glyph-idle.png art/glyph-warning.png art/glyph-takeover.png art/tug.png art/tug-head.png
RUNTIME_ART += art/glyph-nap.png art/glyph-doze.png art/glyph-bow.png art/glyph-leap.png
RUNTIME_ART += $(wildcard art/outfit-*.png)
SOUNDS := sounds/tug-woof.caf sounds/tug-barking.caf
SOUNDS += $(wildcard sounds/melody-*.caf)

.PHONY: build test app zip dmg run demo melodies clean

build:
	swift build

test:
	swift build
	swift test

$(ICNS): art/app-icon.png
	rm -rf $(ICONSET)
	mkdir -p $(ICONSET)
	for size in 16 32 128 256 512; do \
		sips -z $$size $$size art/app-icon.png --out $(ICONSET)/icon_$${size}x$${size}.png >/dev/null; \
		sips -z $$((size * 2)) $$((size * 2)) art/app-icon.png --out $(ICONSET)/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns $(ICONSET) -o $(ICNS)

app: $(ICNS)
	swift build -c release $(ARCH_FLAGS)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(ICNS) $(APP)/Contents/Resources/AppIcon.icns
	cp $(RUNTIME_ART) $(SOUNDS) $(APP)/Contents/Resources/
	cp "$$(swift build -c release $(ARCH_FLAGS) --show-bin-path)/Sheepdog" $(APP)/Contents/MacOS/Sheepdog
	cp Sources/Sheepdog/Info.plist $(PLIST)
	/usr/libexec/PlistBuddy -c "Set :SheepdogMicrosoftClientID '$(SHEEPDOG_MICROSOFT_CLIENT_ID)'" $(PLIST)
	/usr/libexec/PlistBuddy -c "Set :SheepdogGoogleClientID '$(SHEEPDOG_GOOGLE_CLIENT_ID)'" $(PLIST)
	/usr/libexec/PlistBuddy -c "Set :SheepdogGoogleClientSecret '$(SHEEPDOG_GOOGLE_CLIENT_SECRET)'" $(PLIST)
	/usr/libexec/PlistBuddy -c "Set :SheepdogSupportURL '$(SHEEPDOG_SUPPORT_URL)'" $(PLIST)
	codesign --force --options runtime $(TIMESTAMP) --entitlements $(ENTITLEMENTS) --sign "$(SIGN_ID)" $(APP)

zip: app
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)

dmg:
	rm -f $(DMG)
	$(DMGBUILD) -s dmg.py -D app=$(APP) "Sheepdog" $(DMG)
	$(if $(filter-out -,$(SIGN_ID)),codesign --force --sign "$(SIGN_ID)" --timestamp $(DMG))

demo:
	$(MAKE) app APP=$(DEMO_APP)
	rm -rf .build/demo-frames
	$(DEMO_APP)/Contents/MacOS/Sheepdog --render-demo .build/demo-frames
	ffmpeg -loglevel error -y -framerate 12 -i .build/demo-frames/frame-%04d.png \
		-vf "scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
		-loop 0 art/demo.gif
	$(DEMO_APP)/Contents/MacOS/Sheepdog --render-stills art

melodies:
	python3 sounds/melodies.py

run: app
	-pkill -x Sheepdog
	open $(APP)

clean:
	rm -rf .build
