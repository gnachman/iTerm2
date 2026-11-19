// expect: -Wtautological-compare
#import "iTermStrictWarnings.h"
int f(int x) { return x == x; }
