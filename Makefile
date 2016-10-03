PATH := /usr/bin:/bin:/usr/sbin:/sbin

ORIG_PATH := $(PATH)
PATH := /usr/bin:/bin:/usr/sbin:/sbin
ITERM_PID=$(shell pgrep "iTerm2")
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
	/Developer/usr/bin/gdb build/Development/iTerm2.app/Contents/MacOS/iTerm

TAGS:
	find . -name "*.[mhMH]" -exec etags -o ./TAGS -a '{}' +

install: | Deployment backup-old-iterm
	cp -R build/Deployment/iTerm2.app $(APPS)

Development:
	echo "Using PATH for build: $(PATH)"
	xcodebuild -parallelizeTargets -target iTerm2 -configuration Development && \
	chmod -R go+rX build/Development

Dep:
	xcodebuild -parallelizeTargets -target iTerm2 -configuration Deployment

Deployment:
	xcodebuild -parallelizeTargets -target iTerm2 -configuration Deployment && \
	chmod -R go+rX build/Deployment

Nightly: force
	cp plists/nightly-iTerm2.plist plists/iTerm2.plist
	xcodebuild -parallelizeTargets -target iTerm2 -configuration Nightly && \
	git checkout -- plists/iTerm2.plist
	chmod -R go+rX build/Nightly

run: Development
	build/Development/iTerm2.app/Contents/MacOS/iTerm2

devzip: Development
	cd build/Development && \
	zip -r iTerm2-$(NAME).zip iTerm2.app

zip: Deployment
	cd build/Deployment && \
	zip -r iTerm2-$(NAME).zip iTerm2.app

clean:
	xcodebuild -parallelizeTargets -alltargets clean
	rm -rf build
	rm -f *~

backup-old-iterm:
	if [[ -d $(APPS)/iTerm2.app.bak ]] ; then rm -fr $(APPS)/iTerm2.app.bak ; fi
	if [[ -d $(APPS)/iTerm2.app ]] ; then \
	/bin/mv $(APPS)/iTerm2.app $(APPS)/iTerm2.app.bak ;\
	 cp $(ITERM_CONF_PLIST) $(APPS)/iTerm2.app.bak/Contents/ ; \
	fi

restart:
	PATH=$(ORIG_PATH) /usr/bin/open /Applications/iTerm2.app &
	/bin/kill -TERM $(ITERM_PID)

canary:
	cp canary-iTerm2.plist iTerm2.plist
	make Deployment
	./canary.sh

release:
	echo "You need to unlock your keychain for signing to work."
	security unlock-keychain ~/Library/Keychains/login.keychain
	cp plists/release-iTerm2.plist plists/iTerm2.plist
	make Deployment

preview:
	echo "You need to unlock your keychain for signing to work."
	security unlock-keychain ~/Library/Keychains/login.keychain
	cp plists/preview-iTerm2.plist plists/iTerm2.plist
	make Deployment

force:
