all:
	xcodebuild -parallelizeTargets -target ColorPicker -configuration Release
	rm -rf ColorPicker.framework
	mv build/Release/ColorPicker.framework .
