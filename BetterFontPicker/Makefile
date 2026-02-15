CODESIGN_FLAGS ?= CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
JOBS ?= -jobs $(shell sysctl -n hw.ncpu)
DEST_DIR ?= .

all:
	xcodebuild -parallelizeTargets -target BetterFontPicker -configuration Release 'CONFIGURATION_BUILD_DIR=$$(SRCROOT)/Build/$$(CONFIGURATION)' $(CODESIGN_FLAGS) $(JOBS)
	rm -rf $(DEST_DIR)/BetterFontPicker.framework
	mv build/Release/BetterFontPicker.framework $(DEST_DIR)/
dev:
	xcodebuild -parallelizeTargets -target BetterFontPicker -configuration Debug 'CONFIGURATION_BUILD_DIR=$$(SRCROOT)/Build/$$(CONFIGURATION)' $(CODESIGN_FLAGS) $(JOBS)
	rm -rf BetterFontPicker.framework
	mv build/Debug/BetterFontPicker.framework .
