#!/bin/tcsh
foreach x (~/Library/ApplicationSupport/iTerm2/iterm2env*/versions/*/lib/python*/site-packages/ /usr/local/lib/python*/site-packages/ ~/Library/Python/*/lib/python/site-packages/ /Library/Python/3.7/site-packages/)
    test -d $x && echo to: $x
    test -d $x && cp -f api/library/python/iterm2/iterm2/* $x/iterm2
    test -d $x && cp -f api/library/python/iterm2-core/iterm2-core/* $x/iterm2-core
end
