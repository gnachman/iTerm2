#!/bin/tcsh
foreach x (~/Library/ApplicationSupport/iTerm2/iterm2env*/versions/*/lib/python3.7/site-packages/iterm2/)
    echo copy to $x
cp api/library/python/iterm2/iterm2/* $x
end

test -d /usr/local/lib/python3.7/site-packages/iterm2 && \
echo cp api/library/python/iterm2/iterm2/* /usr/local/lib/python3.7/site-packages/iterm2
