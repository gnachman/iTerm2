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
	cd build/Deployment/ && zip -r Therm.app.zip Therm.app
	mv build/Deployment/Therm.app.zip .

TAGS:
	find . -name "*.[mhMH]" -exec etags -o ./TAGS -a '{}' +

install: | Deployment backup-old-iterm
	cp -R build/Deployment/Therm.app $(APPS)

Development:
	echo "Using PATH for build: $(PATH)"
	xcodebuild -parallelizeTargets -target Therm -configuration Development && \
	chmod -R go+rX build/Development

Dep:
	xcodebuild -parallelizeTargets -target Therm -configuration Deployment

Deployment:
	xcodebuild -parallelizeTargets -target Therm -configuration Deployment && \
	chmod -R go+rX build/Deployment

Nightly: force
	cp plists/nightly-Therm.plist plists/Therm.plist
	xcodebuild -parallelizeTargets -target Therm -configuration Nightly CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO && \
	git checkout -- plists/Therm.plist
	chmod -R go+rX build/Nightly

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

backup-old-iterm:
	if [[ -d $(APPS)/Therm.app.bak ]] ; then rm -fr $(APPS)/Therm.app.bak ; fi
	if [[ -d $(APPS)/Therm.app ]] ; then \
	/bin/mv $(APPS)/Therm.app $(APPS)/Therm.app.bak ;\
	 cp $(ITERM_CONF_PLIST) $(APPS)/Therm.app.bak/Contents/ ; \
	fi

restart:
	PATH=$(ORIG_PATH) /usr/bin/open /Applications/Therm.app &
	/bin/kill -TERM $(ITERM_PID)

canary:
	cp canary-Therm.plist Therm.plist
	$(MAKE) Deployment
	./canary.sh

release:
	cp plists/release-Therm.plist plists/Therm.plist
	$(MAKE) Deployment

preview:
	cp plists/preview-Therm.plist plists/Therm.plist
	$(MAKE) Deployment
force:
