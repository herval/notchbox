# Notchbox: everyday commands. Run `make` to list them.

.DEFAULT_GOAL := help
.PHONY: help install run preview build package package-signed release release-secrets install-app check test test-app clean

APP := build/Notchbox.app
BUNDLE_ID := dev.littleguys.notchbox
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
APPS ?= /Applications

help: ## List the commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-16s %s\n", $$1, $$2}'

install: ## Fetch dependencies (needs Xcode 26 / Swift 6.2+)
	@command -v swift >/dev/null || { echo "Swift not found: install Xcode 26 or later"; exit 1; }
	swift package --force-resolved-versions resolve

run: ## Build a debug Notchbox.app and run it in this terminal (Ctrl-C quits)
	Scripts/build-app.sh debug
	$(APP)/Contents/MacOS/Notchbox

preview: ## Render the panel to build/notchbox-preview.png, without capturing the desktop
	@test -x $(APP)/Contents/MacOS/Notchbox || Scripts/build-app.sh debug
	NOTCHBOX_PREVIEW_PATH="$(CURDIR)/build/notchbox-preview.png" $(APP)/Contents/MacOS/Notchbox --render-preview
	@echo "Wrote build/notchbox-preview.png"

build: ## Build Notchbox.app (universal: Apple silicon + Intel), ad-hoc signed
	Scripts/build-app.sh release "$(CURDIR)/$(APP)" universal

package: ## Package an unsigned universal ZIP and check it, as CI does (never publish it)
	Scripts/package-release.sh --unsigned v$(VERSION)
	Scripts/check-release.sh v$(VERSION) build/release-unsigned

package-signed: ## Sign, notarize and check a local ZIP without publishing
	Scripts/package-release.sh v$(VERSION)
	Scripts/check-release.sh v$(VERSION) build/release --notarized

release: ## Publish the Info.plist version to GitHub Releases and update the Homebrew tap
	Scripts/publish-release.sh v$(VERSION)

release-secrets: ## One-time: configure Keychain notarization and the GitHub tap secret
	Scripts/release-secrets.sh

install-app: ## Build Notchbox.app for this Mac and put it in /Applications, quitting a running copy first
	Scripts/build-app.sh release
	@if pgrep -qx Notchbox; then osascript -e 'tell application id "$(BUNDLE_ID)" to quit' >/dev/null 2>&1; sleep 2; pkill -x Notchbox || true; fi
	rm -rf "$(APPS)/Notchbox.app"
	cp -R $(APP) "$(APPS)/"
	@echo "Installed $(APPS)/Notchbox.app"

check: ## Check shell script syntax and compile the app
	@for script in Scripts/*.sh; do bash -n "$$script" || exit 1; done
	swift build --force-resolved-versions

test: ## Run the unit tests
	swift test --force-resolved-versions

test-app: ## Run the GUI integration checks in a separate test app (needs a logged-in session)
	Scripts/test-app.sh

clean: ## Remove build output
	rm -rf build
	swift package clean
