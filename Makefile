PATH := /usr/bin:/bin:/usr/sbin:/sbin

ORIG_PATH := $(PATH)
PATH := /usr/bin:/bin:/usr/sbin:/sbin
ITERM_PID=$(shell pgrep "Therm2")
APPS := /Applications
ITERM_CONF_PLIST = $(HOME)/Library/Preferences/com.googlecode.iterm2.plist
COMPACTDATE=$(shell date +"%Y%m%d")
VERSION = $(shell cat version.txt | sed -e "s/%(extra)s/$(COMPACTDATE)/")
NAME=$(shell echo $(VERSION) | sed -e "s/\\./_/g")

.PHONY: clean all backup-old-iterm restart

all: Development
dev: Development
prod: Deployment
debug: Development
	/Developer/usr/bin/gdb build/Development/Therm.app/Contents/MacOS/Therm

dist: prod
ifeq ($(shell whoami),pancake)
	codesign -f -s 'J5PTVY8BHH' build/Deployment/Therm.app/Contents/MacOS/Therm
endif
	cd build/Deployment/ && zip -r Therm.app.zip Therm.app
	mv build/Deployment/Therm.app.zip Therm-$(VERSION).zip

config.h: version.txt
	echo "#define THERM_VERSION \"`cat version.txt`\"" > config.h

install: | Deployment backup-old-iterm
	cp -R build/Deployment/Therm.app $(APPS)

Development: config.h
	rm -rf build/Development/Therm.app
	echo "Using PATH for build: $(PATH)"
	cd ColorPicker && xcodebuild
	xcodebuild -parallelizeTargets -target Therm -configuration Development && \
	chmod -R go+rX build/Development
	mkdir -p build/Development/Therm.app/Contents/Frameworks/
	cp -rf ColorPicker/ColorPicker.framework build/Development/Therm.app/Contents/Frameworks/

Dep:
	xcodebuild -parallelizeTargets -target Therm -configuration Deployment

Deployment:
	rm -rf build/Deployment/Therm.app
	xcodebuild -parallelizeTargets -target Therm -configuration Deployment && \
	chmod -R go+rX build/Deployment
	mkdir -p build/Deployment/Therm.app/Contents/Frameworks/
	cp -rf ColorPicker/ColorPicker.framework build/Deployment/Therm.app/Contents/Frameworks/

run: Development
	build/Development/Therm.app/Contents/MacOS/Therm

devzip: Development
	cd build/Development && \
	zip -r Therm-$(NAME).zip Therm.app

zip: Deployment
	cd build/Deployment && \
	zip -r Therm-$(NAME).zip Therm.app

clean:
	xcodebuild -parallelizeTargets -alltargets clean
	rm -rf build
	rm -f *~

restart:
	PATH=$(ORIG_PATH) /usr/bin/open /Applications/Therm.app &
	/bin/kill -TERM $(ITERM_PID)

release:
	cp plists/release-Therm.plist plists/Therm.plist
	$(MAKE) Deployment

todo:
	git grep PANCAKE
