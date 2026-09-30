APP_NAME          := Resticker
BUNDLE_ID         := one.m8n.resticker
INSTALL_DIR       := $(HOME)/Applications
INSTALLED_APP     := $(INSTALL_DIR)/$(APP_NAME).app
KEYCHAIN_SERVICE  := resticker
VERSION           ?= main
-include .env
export

# ARCH selects a cross-compilation target (e.g. "arm64" or "x86_64") and builds
# into an arch-specific scratch/output dir so both can be built without clobbering
# each other. Leave unset for a plain native build in the usual .build/dist paths.
ARCH ?=
ifeq ($(ARCH),)
BUILD_DIR         := .build/release
APP_BUNDLE        := dist/$(APP_NAME).app
SWIFT_BUILD_FLAGS :=
else
BUILD_DIR         := .build-$(ARCH)/release
APP_BUNDLE        := dist/$(ARCH)/$(APP_NAME).app
SWIFT_BUILD_FLAGS := --arch $(ARCH) --scratch-path .build-$(ARCH)
endif

# "-" ad-hoc signs the app, which is enough to run it locally. Override with your own
# identity (e.g. "Apple Development: you@example.com (TEAMID)") for a signed build.
# Set CODESIGN_IDENTITY in .env (see .env.example) to avoid the keychain access prompt
# that a changing ad-hoc signature causes on every reinstall.
CODESIGN_IDENTITY ?= -

.PHONY: all build test bundle install run stop uninstall clean

all: bundle

build:
	swift build -c release $(SWIFT_BUILD_FLAGS)

test:
	swift test

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	codesign --force --identifier $(BUNDLE_ID) --sign "$(CODESIGN_IDENTITY)" $(APP_BUNDLE)
	@echo "built $(APP_BUNDLE)"

install: bundle stop
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALLED_APP)
	cp -R $(APP_BUNDLE) $(INSTALLED_APP)
	@echo "installed $(INSTALLED_APP)"
	@echo "next: open the app and finish setup in its menu bar item's Settings…"

run: install
	open $(INSTALLED_APP)

stop:
	-@pkill -x $(APP_NAME) 2>/dev/null || true

uninstall: stop
	rm -rf $(INSTALLED_APP)
	@echo "removed $(INSTALLED_APP)"
	@echo "settings (UserDefaults) and keychain items were left in place"
	@echo "remove the keychain items with:"
	@echo "  security delete-generic-password -s $(KEYCHAIN_SERVICE) -a repository-password"
	@echo "  security delete-generic-password -s $(KEYCHAIN_SERVICE) -a environment-variables"

clean:
	rm -rf .build .build-* dist
