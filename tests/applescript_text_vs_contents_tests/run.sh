#!/bin/tcsh
foreach x (test*)
  (osascript $x |& grep secret > /dev/null) && echo pass $x || echo fail $x
end

