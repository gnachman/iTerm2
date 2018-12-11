#!/bin/tcsh
foreach x (~/Library/ApplicationSupport/iTerm2/iterm2env*/versions/*/lib/python3.7/site-packages/iterm2/)
cp api/library/python/iterm2/iterm2/* $x
end
