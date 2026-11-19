// expect: -Wtautological-unsigned-zero-compare
#import "iTermStrictWarnings.h"
int f(unsigned x) { return x >= 0; }
