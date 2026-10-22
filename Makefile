APP := .build/Sheepdog.app
SIGN_ID ?= -

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
	cp Sources/Sheepdog/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign "$(SIGN_ID)" $(APP)

run: app
	-pkill -x Sheepdog
	open $(APP)

clean:
	rm -rf .build
