// expect: -Wshadow
#import "iTermStrictWarnings.h"
int x;
int f(void) { int x = 1; return x; }
