#!/bin/tcsh
# Run this from the directory with the failed golden files.
foreach x ( *png )
  echo $x | sed -e 's,\(failed-\)\(.*\),cp \1\2 /Users/gnachman/git/iterm2/tests/Goldens/PTYTextViewTest-golden-travis-\2,'
end

