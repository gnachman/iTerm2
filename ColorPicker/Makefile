CODESIGN_FLAGS ?= CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
JOBS ?= -jobs $(shell sysctl -n hw.ncpu)
DEST_DIR ?= .

all:
	xcodebuild -parallelizeTargets -target ColorPicker -configuration Release 'CONFIGURATION_BUILD_DIR=$$(SRCROOT)/Build/$$(CONFIGURATION)' $(CODESIGN_FLAGS) $(JOBS)
	rm -rf $(DEST_DIR)/ColorPicker.framework
	mv build/Release/ColorPicker.framework $(DEST_DIR)/
