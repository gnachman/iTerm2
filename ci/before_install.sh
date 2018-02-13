#!/usr/bin/env bash

set -x

# Decrypt the dropbox uploader dotfile and copy it to the home directory on
# Travis. The environment vars are magically set when running in travis and
# contain a symmetric key. This came from:
# https://labs.consol.de/travis/dropbox/2015/11/04/upload-travis-artifacts-to-dropbox.html
openssl aes-256-cbc -K $encrypted_ac2a5ce6c7ef_key -iv $encrypted_ac2a5ce6c7ef_iv -in tools/.dropbox_uploader.enc -out ~/.dropbox_uploader -d

bundle config build.nokogiri --use-system-libraries --with-xml2-include=/usr/include/libxml2
