all:
	xcodebuild -parallelizeTargets -target ColorPicker -configuration Release 'CONFIGURATION_BUILD_DIR=$$(SRCROOT)/Build/$$(CONFIGURATION)'
	rm -rf ColorPicker.framework
	mv build/Release/ColorPicker.framework .
