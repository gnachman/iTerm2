#!/bin/tcsh
foreach x (~/Library/ApplicationSupport/iTerm2/iterm2env*/versions/*/lib/python*/site-packages/iterm2/ /usr/local/lib/python*/site-packages/iterm2 ~/Library/Python/*/lib/python/site-packages/iterm2 /Library/Python/3.7/site-packages/iterm2)
    test -d $x && echo to: $x
    test -d $x && cp -f api/library/python/iterm2/iterm2/* $x
end
