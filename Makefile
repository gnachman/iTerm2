PATH := /usr/bin:/bin:/usr/sbin:/sbin

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
	rm -f *~

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
	cd submodules/libsixel && make clean
	cd submodules/libsixel && CC="/usr/bin/clang -target x86_64-apple-macos10.14" LDFLAGS="-ld64 -target x86_64-apple-macos10.14" CFLAGS="-target x86_64-apple-macos10.14" ./configure -host=x86_64-apple-darwin --prefix=${PWD}/ThirdParty/libsixel --without-libcurl --without-jpeg --without-png --disable-python
	cd submodules/libsixel && CC="/usr/bin/clang -target x86_64-apple-macos10.14" LDFLAGS="-ld64 -target x86_64-apple-macos10.14" CFLAGS="-target x86_64-apple-macos10.14" make
	cd submodules/libsixel && make install

	rm ThirdParty/libsixel/lib/*dylib* ThirdParty/libsixel/bin/*
	mv ThirdParty/libsixel/lib/libsixel.a ThirdParty/libsixel/lib/libsixel-x86.a

armsixel: force
	cd submodules/libsixel && ./configure
	cd submodules/libsixel && make clean
	cd submodules/libsixel && LDFLAGS="-ld64 -target arm64-apple-macos10.14" CFLAGS="-target arm64-apple-macos10.14" LIBTOOLFLAGS="-target arm64-apple-macos10.14" ./configure --host=aarch64-apple-darwin --prefix=${PWD}/ThirdParty/libsixel-arm --without-libcurl --without-jpeg --without-png --disable-python --disable-shared && CFLAGS="-target arm64-apple-macos10.14" make && make install
	rm ThirdParty/libsixel-arm/bin/*

# Usage: go to an intel mac and run make x86libsixel and commit it. Go to an arm mac and run make armsixel && make libsixel.
fatlibsixel: force
	make armsixel
	make x86libsixel
	lipo -create -output ThirdParty/libsixel/lib/libsixel.a ThirdParty/libsixel-arm/lib/libsixel.a ThirdParty/libsixel/lib/libsixel-x86.a

armopenssl: force
	cd submodules/openssl && ./Configure darwin64-arm64-cc -Wl,-ld64 && make clean && make build_generated && make libcrypto.a libssl.a -j4 && mv libcrypto.a libcrypto-arm64.a && mv libssl.a libssl-arm64.a

x86openssl: force
	cd submodules/openssl && ./Configure darwin64-x86_64-cc -Wl,-ld64 && make clean && make build_generated && make libcrypto.a libssl.a -j4 && mv libcrypto.a libcrypto-x86_64.a && mv libssl.a libssl-x86_64.a

fatopenssl: force
	make x86openssl
	make armopenssl
	cd submodules/openssl/ && lipo -create -output libcrypto.a libcrypto-x86_64.a libcrypto-arm64.a
	cd submodules/openssl/ && lipo -create -output libssl.a libssl-x86_64.a libssl-arm64.a

x86libssh2: force
	mkdir -p submodules/libssh2/build_x86_64
	# -target x86_64-apple-macos10.15 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
	cd submodules/libssh2/build_x86_64 && /usr/local/bin/cmake -DOPENSSL_ROOT_DIR=${PWD}/submodules/openssl -DBUILD_EXAMPLES=NO -DBUILD_TESTING=NO -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCRYPTO_BACKEND=OpenSSL -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15 -DCMAKE_EXE_LINKER_FLAGS="-ld64" -DCMAKE_MODULE_LINKER_FLAGS="-ld64" -DCMAKE_C_FLAGS="-target x86_64-apple-macos10.15 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" -DCMAKE_CXX_FLAGS="-target x86_64-apple-macos10.15 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" .. && make libssh2 -j4

armlibssh2: force
	mkdir -p submodules/libssh2/build_arm64
	cd submodules/libssh2/build_arm64 && /usr/local/bin/cmake -DOPENSSL_ROOT_DIR=${PWD}/submodules/openssl -DBUILD_EXAMPLES=NO -DBUILD_TESTING=NO -DCMAKE_OSX_ARCHITECTURES=arm64 -DCRYPTO_BACKEND=OpenSSL  -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15 -DCMAKE_EXE_LINKER_FLAGS="-ld64" -DCMAKE_MODULE_LINKER_FLAGS="-ld64" -DCMAKE_C_FLAGS="-target x86_64-apple-macos10.15 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" -DCMAKE_CXX_FLAGS="-target x86_64-apple-macos10.15 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" .. && make libssh2 -j4

fatlibssh2: force fatopenssl
	make x86libssh2
	make armlibssh2
	cd submodules/libssh2 && lipo -create -output libssh2.a build_arm64/src/libssh2.a build_x86_64/src/libssh2.a
	cp submodules/libssh2/libssh2.a submodules/NMSSH/NMSSH-OSX/Libraries/lib/libssh2.a
	cp submodules/openssl/libcrypto.a submodules/openssl/libssl.a submodules/NMSSH/NMSSH-OSX/Libraries/lib/

CoreParse: force
	rm -rf ThirdParty/CoreParse.framework
	cd submodules/CoreParse && xcodebuild -target CoreParse -configuration Release CONFIGURATION_BUILD_DIR=../../ThirdParty VALID_ARCHS="arm64 x86_64" OTHER_LDFLAGS="-ld64"
	cp "submodules/CoreParse//CoreParse/Tokenisation/Token Recognisers/CPRegexpRecogniser.h" ThirdParty/CoreParse.framework/Versions/A/Headers/CPRegexpRecogniser.h

NMSSH: force fatlibssh2
	rm -rf ThirdParty/NMSSH.framework
	cd submodules/NMSSH && xcodebuild -target NMSSH -project NMSSH.xcodeproj -configuration Release CONFIGURATION_BUILD_DIR=../../ThirdParty OTHER_LDFLAGS="-ld64"

libgit2: force
	mkdir -p submodules/libgit2/build
	MAKE=/usr/local/bin/cmake PATH=/usr/local/bin:${PATH} cd submodules/libgit2/build && ${CMAKE} -DBUILD_SHARED_LIBS=OFF -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" -DCMAKE_OSX_DEPLOYMENT_TARGET="10.14" -DCMAKE_INSTALL_PREFIX=../../../ThirdParty/libgit2 -DUSE_SSH=OFF ..
	MAKE=/usr/local/bin/cmake PATH=/usr/local/bin:${PATH} cd submodules/libgit2/build && ${CMAKE} --build .
	MAKE=/usr/local/bin/cmake PATH=/usr/local/bin:${PATH} cd submodules/libgit2/build && ${CMAKE} --build . --target install

paranoiddeps: force
	/usr/bin/sandbox-exec -f deps.sb make deps

# You probably want make paranoiddeps to avoid depending on Hombrew stuff.
deps: force
	make fatlibsixel
	make fatopenssl
	make fatlibssh2
	make CoreParse
	make NMSSH
	make bindeps
	make libgit2
       
DepsIfNeeded: force
	tools/rebuild-deps-if-needed

powerline-extra-symbols: force
	cp submodules/powerline-extra-symbols/src/*eps ThirdParty/PowerlineExtraSymbols/

bindeps: SwiftyMarkdown Highlightr
	cd BetterFontPicker && make
	cd ColorPicker && make
	cd SearchableComboListView && make

SwiftyMarkdown: force
	cd submodules/SwiftyMarkdown && xcodebuild
	rm -rf ThirdParty/SwiftyMarkdown.framework
	mv submodules/SwiftyMarkdown/build/Release/SwiftyMarkdown.framework ThirdParty/SwiftyMarkdown.framework

Highlightr: force
	cd submodules/Highlightr && xcodebuild -project Highlightr.xcodeproj -target Highlightr-macOS
	rm -rf ThirdParty/Highlightr.framework
	mv submodules/Highlightr/build/Release/Highlightr.framework ThirdParty/Highlightr.framework

force:
