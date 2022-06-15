#!/usr/bin/python3

import os
import time
import subprocess

try:
    del os.environ["MACOSX_DEPLOYMENT_TARGET"]
except KeyError:
    pass
from Foundation import NSMutableDictionary

if os.environ["CONFIGURATION"] == "Development":
    cmd = "git log -1 --format=\"%H\""
    output = subprocess.check_output(cmd, shell=True).decode("utf-8")

    revision = "git.unknown"
    for line in output.split("\n"):
        if len(line.strip()) > 0:
            revision = "git." + line.strip()[:10]
            break

elif os.environ["CONFIGURATION"] == "Nightly":
    revision = time.strftime("%Y%m%d-nightly")
else:
    revision = time.strftime("%Y%m%d")
version = open("version.txt").read().strip() % {"extra": revision}

def update(path):
    plist = NSMutableDictionary.dictionaryWithContentsOfFile_(path)
    print("Updating versions:", path, version)
    if not plist:
        print("WARNING - FAILED TO LOAD PLIST")
    plist["CFBundleShortVersionString"] = version
    plist["CFBundleGetInfoString"] = version
    plist["CFBundleVersion"] = version
    plist.writeToFile_atomically_(path, 1)
    print(plist)


# Update the main app's plist

# /Users/gnachman/git/iterm2/Build/Development
buildDir = os.environ["BUILT_PRODUCTS_DIR"]

# iTerm2.app/Contents/Info.plist
infoFile = os.environ["INFOPLIST_PATH"]

# /Users/gnachman/git/iterm2/Build/Development/iTerm2.app/Contents/Info.plist
path = os.path.join(buildDir, infoFile)

update(path)


# Now update extensions and plugins.

# Contents/PlugIns
BUNDLE_PLUGINS_FOLDER_PATH = os.environ["BUNDLE_PLUGINS_FOLDER_PATH"]

# iTerm2.app/Contents/Frameworks
FRAMEWORKS_FOLDER_PATH = os.environ["FRAMEWORKS_FOLDER_PATH"]

paths = [
    f'{buildDir}/iTermFileProvider.appex/Contents/Info.plist',
    f'{buildDir}/FileProviderService.framework/Versions/A/Resources/Info.plist',
]

for path in paths:
    update(path)

