CODESIGN_FLAGS ?= CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
JOBS ?= -jobs $(shell sysctl -n hw.ncpu)
DEST_DIR ?= .

all: force
	rm -rf $(DEST_DIR)/SearchableComboListView.framework
	xcodebuild -parallelizeTargets -target SearchableComboListView -configuration Release 'CONFIGURATION_BUILD_DIR=$$(SRCROOT)/Build/$$(CONFIGURATION)' $(CODESIGN_FLAGS) $(JOBS)
	mv build/Release/SearchableComboListView.framework $(DEST_DIR)/

force:
