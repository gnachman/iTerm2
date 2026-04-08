ORIG_PATH := $(PATH)
PATH := /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
ITERM_PID=$(shell pgrep "iTerm2")
APPS := /Applications
ITERM_CONF_PLIST = $(HOME)/Library/Preferences/com.googlecode.iterm2.plist
COMPACTDATE=$(shell date +"%Y%m%d")
VERSION = $(shell cat version.txt | sed -e "s/%(extra)s/$(COMPACTDATE)/")
NAME=$(shell echo $(VERSION) | sed -e "s/\\./_/g")
HOMEBREW_PREFIX ?= $(shell brew --prefix 2>/dev/null || echo /opt/homebrew)
CMAKE ?= $(HOMEBREW_PREFIX)/bin/cmake
PKG_CONFIG ?= $(HOMEBREW_PREFIX)/bin/pkg-config
RUSTUP ?= $(shell PATH="$(ORIG_PATH):$(HOME)/.cargo/bin" which rustup 2>/dev/null)
DEPLOYMENT_TARGET=12.0

# Build product directory: defaults to xcodebuild's SYMROOT.
# Override with BUILD_DIR=/path/to/dir on the command line.
# Skip validation for targets that don't need a build directory.
ifndef BUILD_DIR
  BUILD_DIR := $(shell xcodebuild -scheme iTerm2 -showBuildSettings 2>/dev/null | awk -F ' = ' '/^ *SYMROOT/{print $$2; exit}')
endif
_NEEDS_BUILD_DIR := $(if $(filter-out setup dangerous-setup _setup-main help doctor,$(MAKECMDGOALS)),yes,$(if $(MAKECMDGOALS),,yes))
ifdef _NEEDS_BUILD_DIR
  ifeq ($(strip $(BUILD_DIR)),)
    $(error Could not determine BUILD_DIR from xcodebuild -showBuildSettings. Is Xcode installed? Set BUILD_DIR explicitly to override.)
  endif
  ifeq ($(patsubst /%,%,$(BUILD_DIR)),$(BUILD_DIR))
    $(error BUILD_DIR is not an absolute path: $(BUILD_DIR))
  endif
  ifneq ($(shell d='$(BUILD_DIR)'; while [ ! -d "$$d" ]; do d=$$(dirname "$$d"); done; [ -w "$$d" ] && echo ok),ok)
    $(error BUILD_DIR is not writable: $(BUILD_DIR))
  endif
endif

# Code signing: disabled by default (contributor-friendly).
# Use SIGNED=1 to build with the project's signing identity.
ifndef SIGNED
  SIGNING_FLAGS = CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
endif

# Architecture: native-only by default (faster builds).
# Use UNIVERSAL=1 to build universal (arm64 + x86_64) binaries for release.
NATIVE_ARCH := $(shell uname -m)
ifndef UNIVERSAL
  ARCH_FLAGS = ARCHS="$(NATIVE_ARCH)" ONLY_ACTIVE_ARCH=YES
endif

# Architecture for cmake-based deps.
ifdef UNIVERSAL
  CMAKE_ARCHS = x86_64;arm64
else
  CMAKE_ARCHS = $(NATIVE_ARCH)
endif

# Rust target triple for the native architecture.
ifeq ($(NATIVE_ARCH),arm64)
  RUST_NATIVE_TARGET = aarch64-apple-darwin
else
  RUST_NATIVE_TARGET = x86_64-apple-darwin
endif

.PHONY: clean all backup-old-iterm restart setup dangerous-setup _setup-main help doctor

help:
	@echo "iTerm2 — $(VERSION) ($(NATIVE_ARCH))"
	@echo ""
	@echo "First time:"
	@echo "  make setup            Install all build dependencies (interactive)"
	@echo "  make dangerous-setup  Same as setup, skip all confirmations"
	@echo ""
	@echo "Build:"
	@echo "  make              Build Development (default)"
	@echo "  make dev          Build Development"
	@echo "  make prod         Build Deployment"
	@echo "  make run          Build and launch Development build"
	@echo "  make watch        Build and launch with interactive r=reload q=quit loop"
	@echo "  make test         Run unit tests"
	@echo "  make install      Build Deployment and install to /Applications"
	@echo ""
	@echo "Dependencies:"
	@echo "  make paranoid-deps  Rebuild all native dependencies (sandboxed)"
	@echo "  make DepsIfNeeded   Rebuild deps only if Xcode version changed"
	@echo "  make clean        Remove build products"
	@echo "  make cleandeps    Clean submodule build directories"
	@echo ""
	@echo "Release:"
	@echo "  make Beta         Build Beta configuration"
	@echo "  make Nightly      Build Nightly configuration"
	@echo "  make Deployment   Build Deployment configuration"
	@echo ""
	@echo "Diagnose:"
	@echo "  make doctor       Check all build dependencies"
	@echo ""
	@echo "Options:"
	@echo "  SIGNED=1          Enable code signing"
	@echo "  UNIVERSAL=1       Build universal (arm64 + x86_64) binaries"
	@echo "  BUILD_DIR=/path   Override build output directory"
	@echo ""
	@echo "Homebrew: $(HOMEBREW_PREFIX)"

all: Development
dev: Development
prod: Deployment

setup:
	@BREW_BIN=$$(PATH="/opt/homebrew/bin:/usr/local/bin:$(ORIG_PATH)" command -v brew 2>/dev/null); \
	if [ -z "$$BREW_BIN" ]; then \
		echo "Homebrew is not installed."; \
		if [ "$(SKIP_CONFIRM)" != "1" ]; then \
			printf "Install Homebrew via its official install script (requires sudo)? [y/N] "; \
			read ans </dev/tty; case "$$ans" in [yY]) ;; *) echo "Aborted."; exit 1;; esac; \
		fi; \
		NONINTERACTIVE=1 /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; \
		BREW_BIN=$$(command -v /opt/homebrew/bin/brew 2>/dev/null || command -v /usr/local/bin/brew 2>/dev/null); \
		if [ -z "$$BREW_BIN" ]; then \
			echo "Error: Homebrew installation failed."; \
			exit 1; \
		fi; \
	fi; \
	if ! PATH="$(ORIG_PATH)" command -v brew >/dev/null 2>&1; then \
		echo "Restarting setup with Homebrew in PATH..."; \
		PATH="$$(dirname $$BREW_BIN):$(ORIG_PATH)" \
			$(MAKE) _setup-main SKIP_CONFIRM="$(SKIP_CONFIRM)"; \
	else \
		$(MAKE) _setup-main SKIP_CONFIRM="$(SKIP_CONFIRM)"; \
	fi

dangerous-setup:
	@$(MAKE) setup SKIP_CONFIRM=1

_setup-main:
	@XCODE_DEV=$$(PATH="$(ORIG_PATH)" xcode-select -p 2>/dev/null); \
	if echo "$$XCODE_DEV" | grep -q '/Xcode.*\.app'; then \
		XCODE_APP=$$(echo "$$XCODE_DEV" | sed 's|/Contents/Developer.*||'); \
		echo "Xcode already selected: $$XCODE_APP"; \
	else \
		echo "Xcode.app is not selected."; \
		XCODE_APP=$$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1); \
		if [ -n "$$XCODE_APP" ]; then \
			echo "Found $$XCODE_APP, selecting it..."; \
			if [ "$(SKIP_CONFIRM)" != "1" ]; then \
				printf "This will run: sudo xcode-select -s \"$$XCODE_APP\". Continue? [y/N] "; \
				read ans </dev/tty; case "$$ans" in [yY]) ;; *) echo "Aborted."; exit 1;; esac; \
			fi; \
			sudo xcode-select -s "$$XCODE_APP"; \
		else \
			echo "No Xcode installation found in /Applications."; \
			HAS_XCODES=0; \
			if PATH="$(ORIG_PATH)" command -v xcodes >/dev/null 2>&1; then \
				HAS_XCODES=1; \
			else \
				echo "Installing xcodes to manage Xcode versions..."; \
				PATH="$(ORIG_PATH)" brew install aria2 2>&1 || true; \
				if PATH="$(ORIG_PATH)" brew install xcodes 2>&1; then \
					HAS_XCODES=1; \
				else \
					echo "Could not install xcodes. See error above."; \
				fi; \
			fi; \
			if [ "$$HAS_XCODES" = "1" ]; then \
				echo "Downloading and installing the latest Xcode (this will take a while)..."; \
				PATH="$(ORIG_PATH)" xcodes install --latest --experimental-unxip; \
				XCODE_APP=$$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1); \
				if [ -z "$$XCODE_APP" ]; then \
					XCODE_APP=$$(PATH="$(ORIG_PATH)" xcodes installed | tail -1 | awk '{print $$NF}'); \
				fi; \
			fi; \
			if [ -z "$$XCODE_APP" ]; then \
				echo ""; \
				echo "Please install Xcode from the App Store or https://developer.apple.com/download/"; \
				echo "then re-run make setup."; \
				exit 1; \
			fi; \
			if [ "$(SKIP_CONFIRM)" != "1" ]; then \
				printf "This will run: sudo xcode-select -s \"$$XCODE_APP\". Continue? [y/N] "; \
				read ans </dev/tty; case "$$ans" in [yY]) ;; *) echo "Aborted."; exit 1;; esac; \
			fi; \
			sudo xcode-select -s "$$XCODE_APP"; \
		fi; \
	fi
	@if [ "$(SKIP_CONFIRM)" != "1" ]; then \
		printf "Accept the Xcode license agreement? [y/N] "; \
		read ans </dev/tty; \
		case "$$ans" in [yY]) sudo PATH="$(ORIG_PATH)" xcodebuild -license accept;; *) echo "Skipped license acceptance.";; esac; \
	else \
		sudo PATH="$(ORIG_PATH)" xcodebuild -license accept 2>/dev/null || true; \
	fi
	@if [ -z "$(RUSTUP)" ]; then \
		echo "rustup is not installed."; \
		if [ "$(SKIP_CONFIRM)" != "1" ]; then \
			printf "Install rustup via 'curl https://sh.rustup.rs | sh'? [y/N] "; \
			read ans </dev/tty; case "$$ans" in [yY]) ;; *) echo "Aborted."; exit 1;; esac; \
		fi; \
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; \
		export PATH="$$HOME/.cargo/bin:$$PATH"; \
	fi
	@test -f plists/iTerm2.plist || cp plists/dev-iTerm2.plist plists/iTerm2.plist
	@PATH="$(ORIG_PATH)" brew list cmake >/dev/null 2>&1 || PATH="$(ORIG_PATH)" brew install cmake
	@PATH="$(ORIG_PATH)" brew list pkg-config >/dev/null 2>&1 || PATH="$(ORIG_PATH)" brew install pkg-config
	@PATH="$(ORIG_PATH)" brew list automake >/dev/null 2>&1 || PATH="$(ORIG_PATH)" brew install automake
	@PATH="$(ORIG_PATH)" command -v perl >/dev/null 2>&1 || PATH="$(ORIG_PATH)" brew install perl
	@if ! test -x "$(HOMEBREW_PREFIX)/bin/python3"; then \
		PATH="$(ORIG_PATH)" brew install python3; \
		if ! PATH="$(ORIG_PATH)" brew link python@3 2>/dev/null; then \
			echo "brew link python@3 would overwrite existing symlinks:"; \
			PATH="$(ORIG_PATH)" brew link python@3 2>&1 | head -5; \
			if [ "$(SKIP_CONFIRM)" != "1" ]; then \
				printf "Overwrite these symlinks? [y/N] "; \
				read ans </dev/tty; case "$$ans" in [yY]) ;; *) echo "Aborted."; exit 1;; esac; \
			fi; \
			PATH="$(ORIG_PATH)" brew link --overwrite python@3; \
		fi; \
	fi
	@if ! PATH="$(ORIG_PATH)" brew list --cask sf-symbols >/dev/null 2>&1; then \
		INSTALL_SF=1; \
		if [ "$(SKIP_CONFIRM)" != "1" ]; then \
			printf "sf-symbols is a .pkg installer that requires sudo. Install it now? [y/N] "; \
			read ans </dev/tty; case "$$ans" in [yY]) ;; *) INSTALL_SF=0; echo "Skipped sf-symbols.";; esac; \
		fi; \
		if [ "$$INSTALL_SF" = "1" ]; then \
			PATH="$(ORIG_PATH)" brew install --cask sf-symbols || \
			{ echo ""; echo "WARNING: sf-symbols installation failed (requires sudo)."; \
			  echo "  Ask your admin to run: brew install --cask sf-symbols"; echo ""; }; \
		fi; \
	fi
	@$(HOMEBREW_PREFIX)/bin/python3 -c "import objc" 2>/dev/null || $(HOMEBREW_PREFIX)/bin/pip3 install --break-system-packages pyobjc
	@PATH="$(ORIG_PATH):$$HOME/.cargo/bin" command -v cbindgen >/dev/null || $(or $(RUSTUP),$$HOME/.cargo/bin/rustup) run stable cargo install cbindgen
	# Note: this installs arm tooling as well
	$(or $(RUSTUP),$$HOME/.cargo/bin/rustup) target add x86_64-apple-darwin
	git submodule update --init --recursive
	PATH="$(ORIG_PATH)" xcodebuild -downloadComponent MetalToolchain || \
		echo "WARNING: Metal Toolchain download failed. You can retry later with: xcodebuild -downloadComponent MetalToolchain"
	@echo ""
	@echo "Setup complete. Run 'make paranoid-deps' to build native dependencies."

doctor:
	@echo "iTerm2 build environment — $(NATIVE_ARCH)"
	@echo ""
	@printf "  %-18s" "Homebrew:"; (PATH="$(ORIG_PATH)" brew --version 2>/dev/null | head -1) || echo "NOT FOUND"
	@printf "  %-18s" "Homebrew prefix:"; echo "$(HOMEBREW_PREFIX)"
	@printf "  %-18s" "Xcode:"; (xcodebuild -version 2>/dev/null | tr '\n' ' ' && echo) || echo "NOT FOUND"
	@printf "  %-18s" "xcode-select:"; (xcode-select -p 2>/dev/null) || echo "NOT FOUND"
	@printf "  %-18s" "xcodes:"; (PATH="$(ORIG_PATH)" xcodes version 2>/dev/null) || echo "not installed"
	@printf "  %-18s" "cmake:"; ($(CMAKE) --version 2>/dev/null | head -1) || echo "NOT FOUND"
	@printf "  %-18s" "pkg-config:"; ($(PKG_CONFIG) --version 2>/dev/null) || echo "NOT FOUND"
	@printf "  %-18s" "automake:"; (PATH="$(ORIG_PATH)" automake --version 2>/dev/null | grep -m1 .) || echo "NOT FOUND"
	@printf "  %-18s" "perl:"; (PATH="$(ORIG_PATH)" perl -e 'print $$]."\n"' 2>/dev/null) || echo "NOT FOUND"
	@printf "  %-18s" "python3 (brew):"; ver=$$($(HOMEBREW_PREFIX)/bin/python3 --version 2>/dev/null); \
		if [ -z "$$ver" ]; then echo "NOT FOUND — run make setup"; \
		elif echo "$$ver" | grep -q "^Python 3"; then echo "$$ver"; \
		else echo "$$ver (WARNING: needs Python 3)"; fi
	@printf "  %-18s" "pyobjc:"; ($(HOMEBREW_PREFIX)/bin/python3 -c "import objc; print('installed')" 2>/dev/null) || echo "NOT FOUND"
	@printf "  %-18s" "rustup:"; (PATH="$(ORIG_PATH):$(HOME)/.cargo/bin" rustup --version 2>/dev/null) || echo "NOT FOUND"
	@printf "  %-18s" "cbindgen:"; (PATH="$(ORIG_PATH):$(HOME)/.cargo/bin" cbindgen --version 2>/dev/null) || echo "NOT FOUND"
	@printf "  %-18s" "sf-symbols:"; (PATH="$(ORIG_PATH)" brew list --cask sf-symbols >/dev/null 2>&1 && echo "installed") || echo "NOT FOUND"

TAGS:
	find . -name "*.[mhMH]" -exec etags -o ./TAGS -a '{}' +

install: | Deployment backup-old-iterm
	cp -R $(BUILD_DIR)/Deployment/iTerm2.app $(APPS)

Development:
	echo "Using PATH for build: $(PATH)"
	xcodebuild -scheme iTerm2 -configuration Development -destination 'platform=macOS' -skipPackagePluginValidation $(SIGNING_FLAGS) $(ARCH_FLAGS) SYMROOT="$(BUILD_DIR)" && \
	chmod -R go+rX $(BUILD_DIR)/Development

Beta:
	cp plists/beta-iTerm2.plist plists/iTerm2.plist
	xcodebuild -scheme iTerm2 -configuration Beta -destination 'platform=macOS' -skipPackagePluginValidation $(SIGNING_FLAGS) $(ARCH_FLAGS) SYMROOT="$(BUILD_DIR)" ENABLE_ADDRESS_SANITIZER=NO && \
	chmod -R go+rX $(BUILD_DIR)/Beta

Deployment:
	xcodebuild -scheme iTerm2 -configuration Deployment -destination 'platform=macOS' -skipPackagePluginValidation $(SIGNING_FLAGS) $(ARCH_FLAGS) SYMROOT="$(BUILD_DIR)" ENABLE_ADDRESS_SANITIZER=NO && \
	chmod -R go+rX $(BUILD_DIR)/Deployment

Nightly: force
	cp plists/nightly-iTerm2.plist plists/iTerm2.plist
	xcodebuild -scheme iTerm2 -configuration Nightly -destination 'platform=macOS' -skipPackagePluginValidation $(SIGNING_FLAGS) $(ARCH_FLAGS) SYMROOT="$(BUILD_DIR)" ENABLE_ADDRESS_SANITIZER=NO
	chmod -R go+rX $(BUILD_DIR)/Nightly

run: Development
	"$(BUILD_DIR)/Development/iTerm2.app/Contents/MacOS/iTerm2" -suite iterm2-dev

watch: Development
	tools/run.sh "$(BUILD_DIR)/Development/iTerm2.app/Contents/MacOS/iTerm2" "$(BUILD_DIR)" -suite iterm2-dev

devzip: Development
	cd $(BUILD_DIR)/Development && \
	zip -r iTerm2-$(NAME).zip iTerm2.app

zip: Deployment
	cd $(BUILD_DIR)/Deployment && \
	zip -r iTerm2-$(NAME).zip iTerm2.app

clean:
	rm -rf "$(BUILD_DIR)"
	rm -rf submodules/*/build
	rm -rf submodules/*/build-*
	rm -rf submodules/*/build_*
	rm -rf submodules/libssh2/libssh2.a
	rm -f *~
	git -C submodules/NMSSH/ checkout NMSSH-OSX/Libraries/lib/
	rm -rf BetterFontPicker/BetterFontPicker.framework && git checkout BetterFontPicker/BetterFontPicker.framework
	rm -rf ColorPicker/ColorPicker.framework && git checkout ColorPicker/ColorPicker.framework
	rm -rf SearchableComboListView/SearchableComboListView.framework && git checkout SearchableComboListView/SearchableComboListView.framework
	rm -rf ThirdParty && git checkout ThirdParty
	cd submodules/libsixel && make distclean || true
	git checkout last-xcode-version

backup-old-iterm:
	if [[ -d $(APPS)/iTerm2.app.bak ]] ; then rm -fr $(APPS)/iTerm2.app.bak ; fi
	if [[ -d $(APPS)/iTerm2.app ]] ; then \
	/bin/mv $(APPS)/iTerm2.app $(APPS)/iTerm2.app.bak ;\
	 cp $(ITERM_CONF_PLIST) $(APPS)/iTerm2.app.bak/Contents/ ; \
	fi

restart:
	PATH=$(ORIG_PATH) /usr/bin/open /Applications/iTerm2.app &
	/bin/kill -TERM $(ITERM_PID)

release:
	cp plists/release-iTerm2.plist plists/iTerm2.plist
	make Deployment

preview:
	cp plists/preview-iTerm2.plist plists/iTerm2.plist
	make Deployment

x86libsixel: force
	mkdir -p submodules/libsixel/build-x86
	cd submodules/libsixel/build-x86 && PKG_CONFIG=$(PKG_CONFIG) CC="/usr/bin/clang -target x86_64-apple-macos$(DEPLOYMENT_TARGET)" LDFLAGS="-target x86_64-apple-macos$(DEPLOYMENT_TARGET)" CFLAGS="-target x86_64-apple-macos$(DEPLOYMENT_TARGET)" LIBTOOLFLAGS="-target x86_64-apple-macos$(DEPLOYMENT_TARGET)" ../configure -host=x86_64-apple-darwin --prefix=${PWD}/ThirdParty/libsixel-x86 --without-libcurl --without-jpeg --without-png --disable-python --disable-shared && $(MAKE) && $(MAKE) install

armsixel: force
	mkdir -p submodules/libsixel/build-arm
	cd submodules/libsixel/build-arm && PKG_CONFIG=$(PKG_CONFIG) CC="/usr/bin/clang -target arm64-apple-macos$(DEPLOYMENT_TARGET)" LDFLAGS="-target arm64-apple-macos$(DEPLOYMENT_TARGET)" CFLAGS="-target arm64-apple-macos$(DEPLOYMENT_TARGET)" LIBTOOLFLAGS="-target arm64-apple-macos$(DEPLOYMENT_TARGET)" ../configure --host=aarch64-apple-darwin --prefix=${PWD}/ThirdParty/libsixel-arm --without-libcurl --without-jpeg --without-png --disable-python --disable-shared && $(MAKE) && $(MAKE) install

ifdef UNIVERSAL
# Usage: go to an intel mac and run make x86libsixel and commit it. Go to an arm mac and run make armsixel && make libsixel.
fatlibsixel: force armsixel x86libsixel
	lipo -create -output ThirdParty/libsixel/lib/libsixel.a ThirdParty/libsixel-arm/lib/libsixel.a ThirdParty/libsixel-x86/lib/libsixel.a
else
fatlibsixel: force
ifeq ($(NATIVE_ARCH),arm64)
	$(MAKE) armsixel
	cp ThirdParty/libsixel-arm/lib/libsixel.a ThirdParty/libsixel/lib/libsixel.a
else
	$(MAKE) x86libsixel
	cp ThirdParty/libsixel-x86/lib/libsixel.a ThirdParty/libsixel/lib/libsixel.a
endif
endif

armopenssl: force
	echo Begin building configure-armopenssl
	cd submodules/openssl && make clean && make distclean || echo make failed
	cd submodules/openssl && ./Configure darwin64-arm64-cc no-shared -fPIC -mmacosx-version-min=$(DEPLOYMENT_TARGET)
	echo Begin building armopenssl
	cd submodules/openssl && $(MAKE)
	rm -rf submodules/openssl/build-arm
	mkdir submodules/openssl/build-arm
	cp submodules/openssl/*.a submodules/openssl/build-arm

x86openssl: force
	echo Begin building configure-x86openssl
	cd submodules/openssl && make clean && make distclean || echo make failed
	cd submodules/openssl && ./Configure darwin64-x86_64-cc no-shared -fPIC -mmacosx-version-min=$(DEPLOYMENT_TARGET)
	echo Begin building x86openssl
	cd submodules/openssl && $(MAKE)
	rm -rf submodules/openssl/build-x86
	mkdir submodules/openssl/build-x86
	cp submodules/openssl/*.a submodules/openssl/build-x86

ifdef UNIVERSAL
fatopenssl: force
	echo Begin building fatopenssl
	$(MAKE) armopenssl
	$(MAKE) x86openssl
	cd submodules/openssl/ && lipo -create -output libcrypto.a build-x86/libcrypto.a build-arm/libcrypto.a
	cd submodules/openssl/ && lipo -create -output libssl.a build-x86/libssl.a build-arm/libssl.a
	cd submodules/openssl; rm -rf build-fat; mkdir build-fat; mkdir build-fat/lib; cp -R include/ build-fat/include/
	cp submodules/openssl/libcrypto.a submodules/openssl/libssl.a submodules/NMSSH/NMSSH-OSX/Libraries/lib
	cp submodules/openssl/*a submodules/openssl/build-fat/lib
else
fatopenssl: force
	echo Begin building openssl for $(NATIVE_ARCH)
ifeq ($(NATIVE_ARCH),arm64)
	$(MAKE) armopenssl
	cd submodules/openssl; rm -rf build-fat; mkdir -p build-fat/lib; cp -R include/ build-fat/include/
	cp submodules/openssl/build-arm/*.a submodules/openssl/build-fat/lib
	cp submodules/openssl/build-arm/libcrypto.a submodules/openssl/build-arm/libssl.a submodules/NMSSH/NMSSH-OSX/Libraries/lib
else
	$(MAKE) x86openssl
	cd submodules/openssl; rm -rf build-fat; mkdir -p build-fat/lib; cp -R include/ build-fat/include/
	cp submodules/openssl/build-x86/*.a submodules/openssl/build-fat/lib
	cp submodules/openssl/build-x86/libcrypto.a submodules/openssl/build-x86/libssl.a submodules/NMSSH/NMSSH-OSX/Libraries/lib
endif
endif

x86libssh2: force
	echo Begin building x86libssh2
	mkdir -p submodules/libssh2/build_x86_64
	# Add this flag to enable tracing:
	# -DCMAKE_C_FLAGS="-DLIBSSH2DEBUG"
	cd submodules/libssh2/build_x86_64 && $(CMAKE) -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew -DCMAKE_OSX_SYSROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -DOPENSSL_INCLUDE_DIR=${PWD}/submodules/openssl/build-fat/include -DOPENSSL_ROOT_DIR=${PWD}/submodules/openssl/build-fat -DBUILD_EXAMPLES=NO -DBUILD_TESTING=NO -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCRYPTO_BACKEND=OpenSSL -DCMAKE_OSX_DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET) .. && $(MAKE) libssh2_static

armlibssh2: force
	echo Begin building armlibssh2
	mkdir -p submodules/libssh2/build_arm64
	# Add this flag to enable tracing:
	# -DCMAKE_C_FLAGS="-DLIBSSH2DEBUG"
	cd submodules/libssh2/build_arm64 && $(CMAKE) -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew -DCMAKE_OSX_SYSROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -DOPENSSL_INCLUDE_DIR=${PWD}/submodules/openssl/include -DOPENSSL_ROOT_DIR=${PWD}/submodules/openssl -DBUILD_EXAMPLES=NO -DBUILD_TESTING=NO -DCMAKE_OSX_ARCHITECTURES=arm64 -DCRYPTO_BACKEND=OpenSSL -DCMAKE_OSX_DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET) .. && $(MAKE) libssh2_static

ifdef UNIVERSAL
fatlibssh2: force fatopenssl
	echo Begin building fatlibssh2
	$(MAKE) x86libssh2
	$(MAKE) armlibssh2
	cd submodules/libssh2 && lipo -create -output libssh2.a build_arm64/src/libssh2.a build_x86_64/src/libssh2.a
	cp submodules/libssh2/libssh2.a submodules/NMSSH/NMSSH-OSX/Libraries/lib/libssh2.a
else
fatlibssh2: force fatopenssl
	echo Begin building libssh2 for $(NATIVE_ARCH)
ifeq ($(NATIVE_ARCH),arm64)
	$(MAKE) armlibssh2
	cp submodules/libssh2/build_arm64/src/libssh2.a submodules/NMSSH/NMSSH-OSX/Libraries/lib/libssh2.a
else
	$(MAKE) x86libssh2
	cp submodules/libssh2/build_x86_64/src/libssh2.a submodules/NMSSH/NMSSH-OSX/Libraries/lib/libssh2.a
endif
endif

CoreParse: force
	rm -rf ThirdParty/CoreParse.framework
	cd submodules/CoreParse && xcodebuild -target CoreParse -configuration Release CONFIGURATION_BUILD_DIR=../../ThirdParty VALID_ARCHS="arm64 x86_64" $(SIGNING_FLAGS) $(ARCH_FLAGS)
	cp "submodules/CoreParse//CoreParse/Tokenisation/Token Recognisers/CPRegexpRecogniser.h" ThirdParty/CoreParse.framework/Versions/A/Headers/CPRegexpRecogniser.h

NMSSH: force fatlibssh2
	echo Begin building NMSSH
	rm -rf ThirdParty/NMSSH.framework
	cp submodules/libssh2/include/* submodules/NMSSH/NMSSH-OSX/Libraries/include/libssh2
	cd submodules/NMSSH && xcodebuild -target NMSSH -project NMSSH.xcodeproj -configuration Release CONFIGURATION_BUILD_DIR=../../ThirdParty $(SIGNING_FLAGS) $(ARCH_FLAGS)

paranoid-NMSSH: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" NMSSH

ifdef UNIVERSAL
librailroad_dsl: force
	$(RUSTUP) target add x86_64-apple-darwin
	$(RUSTUP) target add aarch64-apple-darwin
	cd submodules/railroad_dsl && $(RUSTUP) run stable cargo build --release --target aarch64-apple-darwin && $(RUSTUP) run stable cargo build --release --target x86_64-apple-darwin && lipo -create target/aarch64-apple-darwin/release/librailroad_dsl.dylib target/x86_64-apple-darwin/release/librailroad_dsl.dylib -output ../../ThirdParty/librailroad_dsl/lib/librailroad_dsl.dylib && cp include/railroad_dsl.h ../../ThirdParty/librailroad_dsl/include && install_name_tool -id @rpath/librailroad_dsl.dylib ../../ThirdParty/librailroad_dsl/lib/librailroad_dsl.dylib
else
librailroad_dsl: force
	$(RUSTUP) target add $(RUST_NATIVE_TARGET)
	cd submodules/railroad_dsl && $(RUSTUP) run stable cargo build --release --target $(RUST_NATIVE_TARGET) && cp target/$(RUST_NATIVE_TARGET)/release/librailroad_dsl.dylib ../../ThirdParty/librailroad_dsl/lib/librailroad_dsl.dylib && cp include/railroad_dsl.h ../../ThirdParty/librailroad_dsl/include && install_name_tool -id @rpath/librailroad_dsl.dylib ../../ThirdParty/librailroad_dsl/lib/librailroad_dsl.dylib
endif

pwmadapters: force
	cd pwmplugin/ && UNIVERSAL=$(UNIVERSAL) ./build.sh

it2cli: force
	cd it2cli/ && UNIVERSAL=$(UNIVERSAL) ./build.sh
	cp it2cli/.build/release/it2 it2cli/bin

libgit2: force
	mkdir -p submodules/libgit2/build
	PATH=/usr/local/bin:${PATH} cd submodules/libgit2/build && ${CMAKE} -DBUILD_CLAR=OFF -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew -DBUILD_SHARED_LIBS=OFF -DCMAKE_OSX_ARCHITECTURES="$(CMAKE_ARCHS)" -DCMAKE_OSX_DEPLOYMENT_TARGET="$(DEPLOYMENT_TARGET)" -DCMAKE_INSTALL_PREFIX=../../../ThirdParty/libgit2 -DUSE_SSH=OFF -DUSE_ICONV=OFF ..
	PATH=/usr/local/bin:${PATH} cd submodules/libgit2/build && ${CMAKE} --build . --target install --parallel "$$(sysctl -n hw.ncpu)"

sparkle: force
	rm -rf ThirdParty/Sparkle.framework
	cd submodules/Sparkle && xcodebuild -scheme Sparkle -configuration Release 'CONFIGURATION_BUILD_DIR=$$(SRCROOT)/Build/$$(CONFIGURATION)' $(SIGNING_FLAGS) $(ARCH_FLAGS)
	mv submodules/Sparkle/Build/Release/Sparkle.framework ThirdParty/Sparkle.framework

paranoid-CoreParse: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" CoreParse

paranoid-SwiftyMarkdown: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" SwiftyMarkdown

paranoid-deps: force
	tools/check-submodule-cleanliness
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" deps
	xcodebuild -version > last-xcode-version

paranoid-fatlibssh2: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" fatlibssh2

paranoid-BetterFontPicker: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" BetterFontPicker

paranoid-BetterFontPicker-Dev: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" BetterFontPicker-Dev

paranoid-libgit2: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" libgit2

paranoid-sparkle: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" sparkle

paranoid-fatlibsixel: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" fatlibsixel

paranoid-librailroad_dsl: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" librailroad_dsl

paranoid-ColorPicker: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" ColorPicker

paranoid-SearchableComboListView: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" SearchableComboListView

paranoid-pwmadapters: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" pwmadapters

# You probably want make paranoid-deps to avoid depending on Homebrew stuff.
deps: force fatlibsixel CoreParse NMSSH bindeps libgit2 sparkle librailroad_dsl sfsymbolenum pwmadapters

sfsymbolenum:
	cp submodules/SFSymbolEnum/Sources/SFSymbolEnum/* ThirdParty/SFSymbolEnum
	cd submodules/SFSymbolEnum && swift generateSFSymbolEnum.swift --objc > ../../ThirdParty/SFSymbolEnum/SFSymbolEnum.h
	cd submodules/SFSymbolEnum && swift generateSFSymbolEnum.swift --objc-impl > ../../ThirdParty/SFSymbolEnum/SFSymbolEnum.m

# Regenerate NSCharacterSet+iTerm.m and iTermCharacterSets.m from latest Unicode data.
# Run this when a new Unicode version is released.
unicode:
	rm -rf tools/.unicode_cache
	python3 tools/generate_nscharacterset.py

DepsIfNeeded: force
	tools/rebuild-deps-if-needed

powerline-extra-symbols: force
	cp submodules/powerline-extra-symbols/src/*eps ThirdParty/PowerlineExtraSymbols/

BetterFontPicker: force
	cd BetterFontPicker && $(MAKE)

BetterFontPicker-Dev: force
	cd BetterFontPicker && $(MAKE) dev

ColorPicker: force
	cd ColorPicker && $(MAKE)

bindeps: SwiftyMarkdown Highlightr BetterFontPicker
	$(MAKE) ColorPicker
	$(MAKE) SearchableComboListView

SearchableComboListView: force
	cd SearchableComboListView && $(MAKE)

SwiftyMarkdown: force
	cd submodules/SwiftyMarkdown && xcodebuild -configuration Release 'CONFIGURATION_BUILD_DIR=$$(SRCROOT)/Build/$$(CONFIGURATION)' $(SIGNING_FLAGS) $(ARCH_FLAGS)
	rm -rf ThirdParty/SwiftyMarkdown.framework
	mv submodules/SwiftyMarkdown/build/Release/SwiftyMarkdown.framework ThirdParty/SwiftyMarkdown.framework

Highlightr: force
	cd submodules/Highlightr && xcodebuild -project Highlightr.xcodeproj -target Highlightr-macOS 'CONFIGURATION_BUILD_DIR=$$(SRCROOT)/Build/$$(CONFIGURATION)' $(SIGNING_FLAGS) $(ARCH_FLAGS)
	rm -rf ThirdParty/Highlightr.framework
	mv submodules/Highlightr/build/Release/Highlightr.framework ThirdParty/Highlightr.framework

cleandeps: force
	cd submodules/CoreParse/ && git clean -f -d .
	cd submodules/NMSSH && git restore .
	cd submodules/SwiftyMarkdown && git restore .
	cd submodules/libsixel && git clean -f -d .
	cd submodules/libssh2 && git clean -f -d .
	cd submodules/openssl && git clean -f -d .

test: force
	tools/run_tests.expect ModernTests

force:
