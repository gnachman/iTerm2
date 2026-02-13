PATH := /usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

ORIG_PATH := $(PATH)
PATH := /usr/bin:/bin:/usr/sbin:/sbin
ITERM_PID=$(shell pgrep "iTerm2")
APPS := /Applications
ITERM_CONF_PLIST = $(HOME)/Library/Preferences/com.googlecode.iterm2.plist
COMPACTDATE=$(shell date +"%Y%m%d")
VERSION = $(shell cat version.txt | sed -e "s/%(extra)s/$(COMPACTDATE)/")
NAME=$(shell echo $(VERSION) | sed -e "s/\\./_/g")
CMAKE ?= /opt/homebrew/bin/cmake
RUSTUP ?= $(shell PATH="$(ORIG_PATH):$(HOME)/.cargo/bin" which rustup 2>/dev/null)
DEPLOYMENT_TARGET=12.0

# Build product directory: defaults to xcodebuild's SYMROOT.
# Override with BUILD_DIR=/path/to/dir on the command line.
ifndef BUILD_DIR
  BUILD_DIR := $(shell xcodebuild -scheme iTerm2 -showBuildSettings 2>/dev/null | awk -F ' = ' '/^ *SYMROOT/{print $$2; exit}')
endif
ifeq ($(strip $(BUILD_DIR)),)
  $(error Could not determine BUILD_DIR from xcodebuild -showBuildSettings. Is Xcode installed? Set BUILD_DIR explicitly to override.)
endif
ifeq ($(patsubst /%,%,$(BUILD_DIR)),$(BUILD_DIR))
  $(error BUILD_DIR is not an absolute path: $(BUILD_DIR))
endif
ifneq ($(shell d='$(BUILD_DIR)'; while [ ! -d "$$d" ]; do d=$$(dirname "$$d"); done; [ -w "$$d" ] && echo ok),ok)
  $(error BUILD_DIR is not writable: $(BUILD_DIR))
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

.PHONY: clean all backup-old-iterm restart

all: Development
dev: Development
prod: Deployment

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
	$(BUILD_DIR)/Development/iTerm2.app/Contents/MacOS/iTerm2

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
	cd submodules/libsixel/build-x86 && PKG_CONFIG=/opt/homebrew/bin/pkg-config CC="/usr/bin/clang -target x86_64-apple-macos$(DEPLOYMENT_TARGET)" LDFLAGS="-target x86_64-apple-macos$(DEPLOYMENT_TARGET)" CFLAGS="-target x86_64-apple-macos$(DEPLOYMENT_TARGET)" LIBTOOLFLAGS="-target x86_64-apple-macos$(DEPLOYMENT_TARGET)" ../configure -host=x86_64-apple-darwin --prefix=${PWD}/ThirdParty/libsixel-x86 --without-libcurl --without-jpeg --without-png --disable-python --disable-shared && $(MAKE) && $(MAKE) install

armsixel: force
	mkdir -p submodules/libsixel/build-arm
	cd submodules/libsixel/build-arm && PKG_CONFIG=/opt/homebrew/bin/pkg-config CC="/usr/bin/clang -target arm64-apple-macos$(DEPLOYMENT_TARGET)" LDFLAGS="-target arm64-apple-macos$(DEPLOYMENT_TARGET)" CFLAGS="-target arm64-apple-macos$(DEPLOYMENT_TARGET)" LIBTOOLFLAGS="-target arm64-apple-macos$(DEPLOYMENT_TARGET)" ../configure --host=aarch64-apple-darwin --prefix=${PWD}/ThirdParty/libsixel-arm --without-libcurl --without-jpeg --without-png --disable-python --disable-shared && $(MAKE) && $(MAKE) install

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
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) NMSSH

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

libgit2: force
	mkdir -p submodules/libgit2/build
	PATH=/usr/local/bin:${PATH} cd submodules/libgit2/build && ${CMAKE} -DBUILD_CLAR=OFF -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew -DBUILD_SHARED_LIBS=OFF -DCMAKE_OSX_ARCHITECTURES="$(CMAKE_ARCHS)" -DCMAKE_OSX_DEPLOYMENT_TARGET="$(DEPLOYMENT_TARGET)" -DCMAKE_INSTALL_PREFIX=../../../ThirdParty/libgit2 -DUSE_SSH=OFF -DUSE_ICONV=OFF ..
	PATH=/usr/local/bin:${PATH} cd submodules/libgit2/build && ${CMAKE} --build . --target install --parallel "$$(sysctl -n hw.ncpu)"

sparkle: force
	rm -rf ThirdParty/Sparkle.framework
	cd submodules/Sparkle && xcodebuild -scheme Sparkle -configuration Release 'CONFIGURATION_BUILD_DIR=$$(SRCROOT)/Build/$$(CONFIGURATION)' $(SIGNING_FLAGS) $(ARCH_FLAGS)
	mv submodules/Sparkle/Build/Release/Sparkle.framework ThirdParty/Sparkle.framework

paranoid-CoreParse: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) CoreParse

paranoid-SwiftyMarkdown: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) SwiftyMarkdown

paranoid-deps: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) deps

paranoid-fatlibssh2: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) fatlibssh2

paranoid-BetterFontPicker: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BetterFontPicker

paranoid-BetterFontPicker-Dev: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BetterFontPicker-Dev

paranoid-libgit2: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) libgit2

paranoid-sparkle: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) sparkle

paranoid-fatlibsixel: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) fatlibsixel

paranoid-librailroad_dsl: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) librailroad_dsl

paranoid-ColorPicker: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) ColorPicker
	
paranoid-SearchableComboListView: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) SearchableComboListView

# You probably want make paranoid-deps to avoid depending on Homebrew stuff.
deps: force fatlibsixel CoreParse NMSSH bindeps libgit2 sparkle librailroad_dsl sfsymbolenum pwmadapters

sfsymbolenum:
	cp submodules/SFSymbolEnum/Sources/SFSymbolEnum/* ThirdParty/SFSymbolEnum
	cd submodules/SFSymbolEnum && swift generateSFSymbolEnum.swift --objc > ../../ThirdParty/SFSymbolEnum/SFSymbolEnum.h
	cd submodules/SFSymbolEnum && swift generateSFSymbolEnum.swift --objc-impl > ../../ThirdParty/SFSymbolEnum/SFSymbolEnum.m

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

force:
