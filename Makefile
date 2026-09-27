APP_NAME          := Resticker
BUNDLE_ID         := net.at6.resticker
INSTALL_DIR       := $(HOME)/Applications
BUILD_DIR         := .build/release
APP_BUNDLE        := dist/$(APP_NAME).app
INSTALLED_APP     := $(INSTALL_DIR)/$(APP_NAME).app
CONFIG_FILE       := $(HOME)/.config/resticker/config.json
KEYCHAIN_SERVICE  := resticker
KEYCHAIN_ACCOUNT  := repository-password
# "-" ad-hoc signs the app, which is enough to run it locally. Override with your own
# identity (e.g. "Apple Development: you@example.com (TEAMID)") for a signed build.
CODESIGN_IDENTITY ?= -

.PHONY: all build test bundle install set-password run stop uninstall clean

all: bundle

build:
	swift build -c release

test:
	swift test

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	codesign --force --identifier $(BUNDLE_ID) --sign "$(CODESIGN_IDENTITY)" $(APP_BUNDLE)
	@echo "built $(APP_BUNDLE)"

install: bundle stop
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALLED_APP)
	cp -R $(APP_BUNDLE) $(INSTALLED_APP)
	@echo "installed $(INSTALLED_APP)"
	@echo "next: make set-password"

# Must run after install. The keychain access list is bound to the installed app path,
# so the item can only pre-authorize an app that already exists.
set-password: 
	@test -d "$(INSTALLED_APP)" || (echo "run 'make install' first"; exit 1)
	@security add-generic-password -U \
		-s $(KEYCHAIN_SERVICE) -a $(KEYCHAIN_ACCOUNT) \
		-T "$(INSTALLED_APP)" -w
	@echo "password stored for service $(KEYCHAIN_SERVICE)"

run: install
	open $(INSTALLED_APP)

stop:
	-@pkill -x $(APP_NAME) 2>/dev/null || true

uninstall: stop
	rm -rf $(INSTALLED_APP)
	@echo "removed $(INSTALLED_APP)"
	@echo "keychain item and $(CONFIG_FILE) were left in place"
	@echo "remove the password with:"
	@echo "  security delete-generic-password -s $(KEYCHAIN_SERVICE) -a $(KEYCHAIN_ACCOUNT)"

clean:
	rm -rf .build dist
