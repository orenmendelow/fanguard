.PHONY: build install uninstall clean cli

APP_NAME = FanGuard
APP_BUNDLE = $(APP_NAME).app
INSTALL_DIR = /Applications
CLI_INSTALL = /usr/local/bin/fan0-killer

build: $(APP_BUNDLE) fan0-killer

$(APP_BUNDLE): Sources/FanGuard.swift Info.plist FanGuard.icns
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp Info.plist $(APP_BUNDLE)/Contents/
	cp FanGuard.icns $(APP_BUNDLE)/Contents/Resources/
	swiftc -o $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) Sources/FanGuard.swift \
		-framework IOKit -framework Cocoa -framework UserNotifications -O

fan0-killer: Sources/fan0-killer.swift
	swiftc -o fan0-killer Sources/fan0-killer.swift -O

install: build
	cp -R $(APP_BUNDLE) $(INSTALL_DIR)/
	cp fan0-killer $(CLI_INSTALL)
	open $(INSTALL_DIR)/$(APP_BUNDLE)
	@echo "Installed. Add to login items with: make login-item"

login-item:
	osascript -e 'tell application "System Events" to make login item at end with properties {path:"$(INSTALL_DIR)/$(APP_BUNDLE)", hidden:true}'

uninstall:
	-osascript -e 'tell application "System Events" to delete login item "$(APP_NAME)"' 2>/dev/null
	-$(CLI_INSTALL) --restore 2>/dev/null
	rm -rf $(INSTALL_DIR)/$(APP_BUNDLE)
	rm -f $(CLI_INSTALL)
	@echo "Uninstalled."

clean:
	rm -rf $(APP_BUNDLE) fan0-killer
