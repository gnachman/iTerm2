#!/bin/bash

# This command came from where all good Apple documentation comes from, which is Twitter.
# From https://twitter.com/rosyna/status/1004418504408252416?lang=en
xcrun altool --eval-app --primary-bundle-id com.googlecode.iterm2 -u apple@georgester.com -f iTerm2.zip

echo Now wait a long time. Paste the UUID into the command below to get progress.

echo xcrun altool --eval-info UUID -u apple@georgester.com

echo ""
echo If it ever finishes, run this:

echo xcrun stapler staple iTerm2.app
echo ""
echo "Then re-zip iTerm2.app and continue on your way."
