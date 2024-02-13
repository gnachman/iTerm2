PATH := /usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

ORIG_PATH := $(PATH)
PATH := /usr/bin:/bin:/usr/sbin:/sbin
ITERM_PID=$(shell pgrep "iTerm2")
APPS := /Applications
ITERM_CONF_PLIST = $(HOME)/Library/Preferences/com.googlecode.iterm2.plist
COMPACTDATE=$(shell date +"%Y%m%d")
VERSION = $(shell cat version.txt | sed -e "s/%(extra)s/$(COMPACTDATE)/")
NAME=$(shell echo $(VERSION) | sed -e "s/\\./_/g")
CMAKE=/usr/local/bin/cmake

.PHONY: clean all backup-old-iterm restart

all: Development
dev: Development
prod: Deployment
debug: Development
	/Developer/usr/bin/gdb build/Development/iTerm2.app/Contents/MacOS/iTerm

TAGS:
	find . -name "*.[mhMH]" -exec etags -o ./TAGS -a '{}' +

install: | Deployment backup-old-iterm
	cp -R build/Deployment/iTerm2.app $(APPS)

Development:
	echo "Using PATH for build: $(PATH)"
	xcodebuild -parallelizeTargets -target iTerm2 -configuration Development && \
	chmod -R go+rX build/Development

Dep:
	xcodebuild -parallelizeTargets -target iTerm2 -configuration Deployment

Beta:
	cp plists/beta-iTerm2.plist plists/iTerm2.plist
	xcodebuild -parallelizeTargets -target iTerm2 -configuration Beta && \
	chmod -R go+rX build/Beta

Deployment:
	xcodebuild -parallelizeTargets -target iTerm2 -configuration Deployment && \
	chmod -R go+rX build/Deployment

Nightly: force
	cp plists/nightly-iTerm2.plist plists/iTerm2.plist
	xcodebuild -parallelizeTargets -target iTerm2 -configuration Nightly
	chmod -R go+rX build/Nightly

run: Development
	build/Development/iTerm2.app/Contents/MacOS/iTerm2

devzip: Development
	cd build/Development && \
	zip -r iTerm2-$(NAME).zip iTerm2.app

zip: Deployment
	cd build/Deployment && \
	zip -r iTerm2-$(NAME).zip iTerm2.app

clean:
	rm -rf build
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

canary:
	cp canary-iTerm2.plist iTerm2.plist
	make Deployment
	./canary.sh

release:
	cp plists/release-iTerm2.plist plists/iTerm2.plist
	make Deployment

preview:
	cp plists/preview-iTerm2.plist plists/iTerm2.plist
	make Deployment

x86libsixel: force
	mkdir -p submodules/libsixel/build-x86
	cd submodules/libsixel/build-x86 && CC="/usr/bin/clang -target x86_64-apple-macos10.14" LDFLAGS="-ld_classic -target x86_64-apple-macos10.14" CFLAGS="-target x86_64-apple-macos10.14" LIBTOOLFLAGS="-target x86_64-apple-macos10.14" ../configure -host=x86_64-apple-darwin --prefix=${PWD}/ThirdParty/libsixel-x86 --without-libcurl --without-jpeg --without-png --disable-python --disable-shared && $(MAKE) && $(MAKE) install

armsixel: force
	mkdir -p submodules/libsixel/build-arm
	cd submodules/libsixel/build-arm && CC="/usr/bin/clang -target arm64-apple-macos10.14" LDFLAGS="-ld_classic -target arm64-apple-macos10.14" CFLAGS="-target arm64-apple-macos10.14" LIBTOOLFLAGS="-target arm64-apple-macos10.14" ../configure --host=aarch64-apple-darwin --prefix=${PWD}/ThirdParty/libsixel-arm --without-libcurl --without-jpeg --without-png --disable-python --disable-shared && $(MAKE) && $(MAKE) install

# Usage: go to an intel mac and run make x86libsixel and commit it. Go to an arm mac and run make armsixel && make libsixel.
fatlibsixel: force armsixel x86libsixel
	lipo -create -output ThirdParty/libsixel/lib/libsixel.a ThirdParty/libsixel-arm/lib/libsixel.a ThirdParty/libsixel-x86/lib/libsixel.a

# Unfortuately configuring these two can't be done in parallel, so force arm to
# go first and have x86 depend on it. (The build is parallel.)
configure-armopenssl: force
	mkdir -p submodules/openssl/build-arm
	cd submodules/openssl/build-arm && ../Configure darwin64-arm64-cc -Wl,-ld_classic && $(MAKE) build_generated

armopenssl: force configure-armopenssl
	cd submodules/openssl/build-arm && $(MAKE) libcrypto.a libssl.a

configure-x86openssl: force configure-armopenssl
	mkdir -p submodules/openssl/build-x86
	cd submodules/openssl/build-x86 && ../Configure darwin64-x86_64-cc -Wl,-ld_classic && $(MAKE) build_generated

x86openssl: force configure-x86openssl
	cd submodules/openssl/build-x86 && $(MAKE) libcrypto.a libssl.a

fatopenssl: force x86openssl armopenssl
	cd submodules/openssl/ && lipo -create -output libcrypto.a build-x86/libcrypto.a build-arm/libcrypto.a
	cd submodules/openssl/ && lipo -create -output libssl.a build-x86/libssl.a build-arm/libssl.a
	# This is a bit of a hack but the files are identical across arches
	ln -sf ../../build-arm/include/openssl/opensslconf.h submodules/openssl/include/openssl/opensslconf.h

x86libssh2: force fatopenssl
	mkdir -p submodules/libssh2/build_x86_64
	cd submodules/libssh2/build_x86_64 && $(CMAKE) -DOPENSSL_ROOT_DIR=${PWD}/submodules/openssl -DBUILD_EXAMPLES=NO -DBUILD_TESTING=NO -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCRYPTO_BACKEND=OpenSSL -DCMAKE_OSX_DEPLOYMENT_TARGET=10.14 -DCMAKE_EXE_LINKER_FLAGS="-ld_classic" -DCMAKE_MODULE_LINKER_FLAGS="-ld_classic" .. && $(MAKE) libssh2_static

armlibssh2: force fatopenssl
	mkdir -p submodules/libssh2/build_arm64
	cd submodules/libssh2/build_arm64 && $(CMAKE) -DOPENSSL_ROOT_DIR=${PWD}/submodules/openssl -DBUILD_EXAMPLES=NO -DBUILD_TESTING=NO -DCMAKE_OSX_ARCHITECTURES=arm64 -DCRYPTO_BACKEND=OpenSSL -DCMAKE_EXE_LINKER_FLAGS="-ld_classic" -DCMAKE_MODULE_LINKER_FLAGS="-ld_classic" -DCMAKE_OSX_DEPLOYMENT_TARGET=10.14 .. && $(MAKE) libssh2_static

fatlibssh2: force x86libssh2 armlibssh2
	cd submodules/libssh2 && lipo -create -output libssh2.a build_arm64/src/libssh2.a build_x86_64/src/libssh2.a
	cp submodules/libssh2/libssh2.a submodules/NMSSH/NMSSH-OSX/Libraries/lib/libssh2.a
	cp submodules/openssl/libcrypto.a submodules/openssl/libssl.a submodules/NMSSH/NMSSH-OSX/Libraries/lib/

CoreParse: force
	rm -rf ThirdParty/CoreParse.framework
	cd submodules/CoreParse && xcodebuild -target CoreParse -configuration Release CONFIGURATION_BUILD_DIR=../../ThirdParty VALID_ARCHS="arm64 x86_64" OTHER_LDFLAGS="-ld_classic"
	cp "submodules/CoreParse//CoreParse/Tokenisation/Token Recognisers/CPRegexpRecogniser.h" ThirdParty/CoreParse.framework/Versions/A/Headers/CPRegexpRecogniser.h

NMSSH: force fatlibssh2
	rm -rf ThirdParty/NMSSH.framework
	cd submodules/NMSSH && xcodebuild -target NMSSH -project NMSSH.xcodeproj -configuration Release CONFIGURATION_BUILD_DIR=../../ThirdParty OTHER_LDFLAGS="-ld_classic"

libgit2: force
	mkdir -p submodules/libgit2/build
	PATH=/usr/local/bin:${PATH} cd submodules/libgit2/build && ${CMAKE} -DBUILD_SHARED_LIBS=OFF -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" -DCMAKE_OSX_DEPLOYMENT_TARGET="10.14" -DCMAKE_INSTALL_PREFIX=../../../ThirdParty/libgit2 -DUSE_SSH=OFF -DUSE_ICONV=OFF ..
	PATH=/usr/local/bin:${PATH} cd submodules/libgit2/build && ${CMAKE} --build . --target install --parallel "$$(sysctl -n hw.ncpu)"

paranoiddeps: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) deps

# You probably want make paranoiddeps to avoid depending on Hombrew stuff.
deps: force fatlibsixel fatopenssl fatlibssh2 CoreParse NMSSH bindeps libgit2 

DepsIfNeeded: force
	tools/rebuild-deps-if-needed

powerline-extra-symbols: force
	cp submodules/powerline-extra-symbols/src/*eps ThirdParty/PowerlineExtraSymbols/

bindeps: SwiftyMarkdown Highlightr
	cd BetterFontPicker && $(MAKE)
	cd ColorPicker && $(MAKE)
	cd SearchableComboListView && $(MAKE)

SwiftyMarkdown: force
	cd submodules/SwiftyMarkdown && xcodebuild -configuration Release
	rm -rf ThirdParty/SwiftyMarkdown.framework
	mv submodules/SwiftyMarkdown/build/Release/SwiftyMarkdown.framework ThirdParty/SwiftyMarkdown.framework

Highlightr: force
	cd submodules/Highlightr && xcodebuild -project Highlightr.xcodeproj -target Highlightr-macOS
	rm -rf ThirdParty/Highlightr.framework
	mv submodules/Highlightr/build/Release/Highlightr.framework ThirdParty/Highlightr.framework

force:
