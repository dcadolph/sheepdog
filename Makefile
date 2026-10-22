APP := .build/Sheepdog.app
SIGN_ID ?= -
PLIST := $(APP)/Contents/Info.plist
SHEEPDOG_MICROSOFT_CLIENT_ID ?=
SHEEPDOG_GOOGLE_CLIENT_ID ?=
SHEEPDOG_GOOGLE_CLIENT_SECRET ?=

.PHONY: build test app run clean

build:
	swift build

test:
	swift build
	swift test

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/Sheepdog $(APP)/Contents/MacOS/Sheepdog
	cp Sources/Sheepdog/Info.plist $(PLIST)
	/usr/libexec/PlistBuddy -c "Set :SheepdogMicrosoftClientID '$(SHEEPDOG_MICROSOFT_CLIENT_ID)'" $(PLIST)
	/usr/libexec/PlistBuddy -c "Set :SheepdogGoogleClientID '$(SHEEPDOG_GOOGLE_CLIENT_ID)'" $(PLIST)
	/usr/libexec/PlistBuddy -c "Set :SheepdogGoogleClientSecret '$(SHEEPDOG_GOOGLE_CLIENT_SECRET)'" $(PLIST)
	codesign --force --sign "$(SIGN_ID)" $(APP)

run: app
	-pkill -x Sheepdog
	open $(APP)

clean:
	rm -rf .build
