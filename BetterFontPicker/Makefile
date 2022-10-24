all:
	xcodebuild -parallelizeTargets -target BetterFontPicker -configuration Release
	rm -rf BetterFontPicker.framework
	mv build/Release/BetterFontPicker.framework .
