#!/bin/tcsh
foreach x ( *.eps )
  echo $x
  convert $x $x.pdf
end
rename -f 's/\.eps\.pdf$/.pdf/' *.eps.pdf
