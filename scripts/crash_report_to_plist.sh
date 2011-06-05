#!/bin/bash

PYTHONPATH="Vendor/ply/ply-3.4/"

export PYTHONPATH
if [[ "$PWD" =~ scripts$ ]]; then
	./crash_report_to_plist.py $@
else
	scripts/crash_report_to_plist.py $@
fi

