#!/bin/bash

cp beta.png nightly.png release.png ../images/AppIcon

cd AppIcon-Beta.appiconset
cp ../beta/icon.iconset/* .
../rename.sh beta

cd ../AppIcon-Nightly.appiconset
cp ../nightly/icon.iconset/* .
../rename.sh nightly

cd ../AppIcon.appiconset
cp ../release/icon.iconset/* .
../rename.sh release

