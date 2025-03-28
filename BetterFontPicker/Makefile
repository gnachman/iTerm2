all:
	xcodebuild -parallelizeTargets -target BetterFontPicker -configuration Release
	rm -rf BetterFontPicker.framework
	mv build/Release/BetterFontPicker.framework .
dev:
	xcodebuild -parallelizeTargets -target BetterFontPicker -configuration Debug
	rm -rf BetterFontPicker.framework
	mv build/Debug/BetterFontPicker.framework .
