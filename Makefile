PATH := /usr/bin:/bin:/usr/sbin:/sbin

ORIG_PATH := $(PATH)
PATH := /usr/bin:/bin:/usr/sbin:/sbin
ITERM_PID=$(shell pgrep "iTerm")
APPS := /Applications
ITERM_CONF_PLIST = $(HOME)/Library/Preferences/com.googlecode.iterm2.plist

XCB_FLAGS =

ifdef LION
	XCB_FLAGS = -sdk macosx10.7 MACOSX_DEPLOYMENT_TARGET=10.7
endif

.PHONY: clean all backup-old-iterm restart

all: Deployment

TAGS:
	find . -name "*.[mhMH]" -exec etags -o ./TAGS -a '{}' +

install: | Deployment backup-old-iterm
	cp -r build/Deployment/iTerm.app $(APPS)

Development:
	echo "Using PATH for build: $(PATH)"
	xcodebuild $(XCB_FLAGS) -parallelizeTargets -alltargets -configuration Development && \
	chmod -R go+rX build/Development

Deployment:
	xcodebuild $(XCB_FLAGS) -parallelizeTargets -alltargets -configuration Deployment && \
	chmod -R go+rX build/Deployment

run: Development
	build/Development/iTerm.app/Contents/MacOS/iTerm

zip: Deployment
	cd build/Deployment && \
	zip -r iTerm_$$(cat ../../version.txt).$$(date '+%Y%m%d').zip iTerm.app

clean:
	xcodebuild $(XCB_FLAGS) -parallelizeTargets -alltargets clean
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

