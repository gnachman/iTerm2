# Code signing: disabled by default (contributor-friendly).
# Use SIGNED=1 to build with the project's signing identity.
ifndef SIGNED
  SIGNING_FLAGS = CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
endif

# Architecture: native-only by default (faster builds).
# Use UNIVERSAL=1 to build universal (arm64 + x86_64) binaries for release.
ifndef UNIVERSAL
  ARCH_FLAGS = ARCHS="$(shell uname -m)" ONLY_ACTIVE_ARCH=YES
endif

all:
	xcodebuild -parallelizeTargets -target ColorPicker -configuration Release 'CONFIGURATION_BUILD_DIR=$$(SRCROOT)/Build/$$(CONFIGURATION)' $(SIGNING_FLAGS) $(ARCH_FLAGS)
	rm -rf ColorPicker.framework
	mv build/Release/ColorPicker.framework .
