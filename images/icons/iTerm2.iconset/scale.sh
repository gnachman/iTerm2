
convert -size 512x512 icon_512x512@2x.png -scale 50% icon_256x256@2x.png
convert -size 512x512 icon_256x256@2x.png -scale 50% icon_128x128@2x.png
convert -size 512x512 icon_128x128@2x.png -scale 50% icon_128x128.png
convert -size 512x512 icon_128x128@2x.png -scale 50% icon_32x32@2x.png
convert -size 512x512 icon_32x32@2x.png -scale 50% icon_16x16@2x.png
convert -size 512x512 icon_16x16@2x.png -scale 50% icon_16x16.png


cp icon_16x16@2x.png icon_32x32.png
cp icon_128x128@2x.png icon_256x256.png
cp icon_256x256@2x.png icon_512x512.png
