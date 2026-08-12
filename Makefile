# Mica — build, sign, install.
#
# Identity settings are load bearing: macOS keys TCC permission grants on bundle ID plus
# the code signature's designated requirement. Changing BUNDLE_ID or signing identity
# resets every permission the app has been granted, so set them once and leave them.

# Local overrides (signing identity, bundle ID, …) live in an untracked Local.mk so a
# clone never inherits someone else's identity. Copy Local.mk.example to Local.mk.
-include Local.mk

APP_NAME      ?= Mica
BUNDLE_ID     ?= com.example.mica
MIN_MACOS     ?= 15.0
# Ad-hoc (`-`) by default so a fresh clone builds with no setup. The downside: ad-hoc
# derives the signature's designated requirement from the cdhash, which changes on every
# build, so macOS treats each build as a new app and TCC permission grants reset. To keep
# grants stable, put a real codesigning identity in Local.mk:
#     SIGN_IDENTITY = Apple Development: Your Name (TEAMID)
SIGN_IDENTITY ?= -

VERSION   := $(shell cat VERSION 2>/dev/null || echo 0.1.0)
BUILD_NUM := $(shell git rev-list --count HEAD 2>/dev/null || date +%Y%m%d%H%M)

BUILD_DIR := .build
DIST_DIR  := dist
APP       := $(DIST_DIR)/$(APP_NAME).app
INSTALLED := /Applications/$(APP_NAME).app
ICNS      := Resources/AppIcon.icns

ICON_SOURCES := Tools/mkicon.swift Sources/Mica/UI/MicaIcon.swift Sources/Mica/UI/SVGPath.swift

export APP_NAME BUNDLE_ID MIN_MACOS VERSION BUILD_NUM

.PHONY: all build test icon bundle sign verify install run clean uninstall reset-tcc dmg release

all: install

build:
	@swift build -c release

test:
	@swift test

icon: $(ICNS)

$(ICNS): $(ICON_SOURCES)
	@echo "==> icon"
	@mkdir -p $(BUILD_DIR) Resources
	@swiftc -O -parse-as-library -o $(BUILD_DIR)/mkicon $(ICON_SOURCES)
	@$(BUILD_DIR)/mkicon $(BUILD_DIR)/AppIcon.iconset
	@iconutil --convert icns $(BUILD_DIR)/AppIcon.iconset --output $(ICNS)
	@echo "  → $(ICNS)"

bundle: build icon
	@Scripts/bundle.sh

sign: bundle
	@echo "==> sign"
	@codesign --force --timestamp=none --identifier "$(BUNDLE_ID)" \
	          --sign "$(SIGN_IDENTITY)" "$(APP)"
	@codesign --verify --strict "$(APP)"
	@echo "  signed as $(BUNDLE_ID)"

# The designated requirement must be byte-identical across rebuilds or TCC will treat
# each build as a new app. If this prints a cdhash, signing fell back to ad-hoc.
verify:
	@codesign -d -r- "$(APP)" 2>&1 | tail -1

install: sign
	@Scripts/install.sh

# Always launch through LaunchServices from /Applications. Running the binary directly
# from a shell makes macOS attribute permission grants to the terminal instead of Mica.
run: install
	@open -a "$(INSTALLED)"

# A drag-to-Applications DMG for distribution. Signs first so the bundle inside is signed;
# for a public download, also notarize (needs a paid Developer ID) or recipients must
# right-click → Open past Gatekeeper the first time.
dmg: sign
	@Scripts/make-dmg.sh
	@echo "  → $(DIST_DIR)/$(APP_NAME).dmg"

# Cuts a release: bumps VERSION, tags, pushes. CI builds the DMG and publishes it.
#   make release BUMP=patch    (or minor / major / an explicit X.Y.Z)
release:
	@Scripts/release.sh $(BUMP)

clean:
	@rm -rf $(BUILD_DIR) $(DIST_DIR) $(ICNS)

uninstall:
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@rm -rf "$(INSTALLED)"
	@echo "removed $(INSTALLED)"

reset-tcc:
	@tccutil reset All $(BUNDLE_ID) || true
