all:
	xcodebuild -parallelizeTargets -target BetterFontPicker -configuration Release 'CONFIGURATION_BUILD_DIR=$$(SRCROOT)/Build/$$(CONFIGURATION)'
	rm -rf BetterFontPicker.framework
	mv build/Release/BetterFontPicker.framework .
dev:
	xcodebuild -parallelizeTargets -target BetterFontPicker -configuration Debug 'CONFIGURATION_BUILD_DIR=$$(SRCROOT)/Build/$$(CONFIGURATION)'
	rm -rf BetterFontPicker.framework
	mv build/Debug/BetterFontPicker.framework .
