PATH := /usr/bin:/bin:/usr/sbin:/sbin

ORIG_PATH := $(PATH)
PATH := /usr/bin:/bin:/usr/sbin:/sbin
ITERM_PID=$(shell pgrep "iTerm")
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
	/Developer/usr/bin/gdb build/Development/iTerm.app/Contents/MacOS/iTerm

TAGS:
	find . -name "*.[mhMH]" -exec etags -o ./TAGS -a '{}' +

install: | Deployment backup-old-iterm
	cp -R build/Deployment/iTerm.app $(APPS)

Development:
	echo "Using PATH for build: $(PATH)"
	xcodebuild -parallelizeTargets -alltargets -configuration Development && \
	chmod -R go+rX build/Development

Dep:
	xcodebuild -parallelizeTargets -alltargets -configuration Deployment

LeopardPPC:
	xcodebuild -parallelizeTargets -alltargets -configuration "Leopard Deployment" && \
	chmod -R go+rX build/"Leopard Deployment"

Deployment:
	xcodebuild -parallelizeTargets -alltargets -configuration Deployment && \
	chmod -R go+rX build/Deployment

Nightly: force
	xcodebuild -parallelizeTargets -alltargets -configuration Nightly && \
	chmod -R go+rX build/Nightly

run: Development
	build/Development/iTerm.app/Contents/MacOS/iTerm

devzip: Development
	cd build/Development && \
	zip -r iTerm2-$(NAME).zip iTerm.app

zip: Deployment
	cd build/Deployment && \
	zip -r iTerm2-$(NAME).zip iTerm.app

clean:
	xcodebuild -parallelizeTargets -alltargets clean
	rm -rf build
	rm -f *~

backup-old-iterm:
	if [[ -d $(APPS)/iTerm.app.bak ]] ; then rm -fr $(APPS)/iTerm.app.bak ; fi
	if [[ -d $(APPS)/iTerm.app ]] ; then \
	/bin/mv $(APPS)/iTerm.app $(APPS)/iTerm.app.bak ;\
	 cp $(ITERM_CONF_PLIST) $(APPS)/iTerm.app.bak/Contents/ ; \
	fi

restart:
	PATH=$(ORIG_PATH) /usr/bin/open /Applications/iTerm.app &
	/bin/kill -TERM $(ITERM_PID)

canary:
	cp canary-iTerm.plist iTerm.plist
	make Deployment
	./canary.sh

release:
	echo "You need to unlock your keychain for signing to work."
	security unlock-keychain ~/Library/Keychains/login.keychain
	cp release-iTerm.plist iTerm.plist
	make Deployment
	cp legacy-iTerm.plist iTerm.plist
	make LeopardPPC
	./release.sh RanFromMakefile

force:
