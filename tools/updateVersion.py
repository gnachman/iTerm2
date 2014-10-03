#!/usr/bin/python

import commands
import os
import sys
import time

try:
        del os.environ["MACOSX_DEPLOYMENT_TARGET"]
except KeyError:
        pass
from Foundation import NSMutableDictionary

if os.environ["CONFIGURATION"] == "Development":
        cmd = "git log -1 --format=\"%H\""
        status, output = commands.getstatusoutput(cmd)
        if status != 0:
                sys.exit(status)

        revision = "git.unknown"
        for line in output.split("\n"):
            if len(line.strip()) > 0:
                revision = "git." + line.strip()[:10]
                break

elif os.environ["CONFIGURATION"] == "Nightly":
        revision = time.strftime("%Y%m%d-nightly")
else:
        revision = time.strftime("%Y%m%d")

buildDir = os.environ["BUILT_PRODUCTS_DIR"]
infoFile = os.environ["INFOPLIST_PATH"]
path = os.path.join(buildDir, infoFile)
plist = NSMutableDictionary.dictionaryWithContentsOfFile_(path)
version = open("version.txt").read().strip() % {"extra": revision}
print "Updating versions:", infoFile, version
plist["CFBundleShortVersionString"] = version
plist["CFBundleGetInfoString"] = version
plist["CFBundleVersion"] = version
plist.writeToFile_atomically_(path, 1)

