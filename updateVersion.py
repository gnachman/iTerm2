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
	status, output = commands.getstatusoutput("bash -l -c 'svn info'")
	if status != 0:
		sys.exit(status)

	for line in output.split("\n"):
		if len(line.strip()) == 0:
			continue
		key, value = [x.lower().strip() for x in line.split(":", 1)]
		if key == "revision":
			revision = "svn" + value
			break
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

