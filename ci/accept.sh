#!/bin/tcsh
# Usage: cd iterm2 && ci/accept.sh /path/to/failures
foreach x ( $1/*png )
  `echo $x | sed -e 's,.*\(failed-\)\(.*\),cp '"$1"'/\1\2 tests/Goldens/PTYTextViewTest-golden-travis-\2,'`
end

