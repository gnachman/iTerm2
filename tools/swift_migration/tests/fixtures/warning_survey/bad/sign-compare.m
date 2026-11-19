// expect: -Wsign-compare
#import "iTermStrictWarnings.h"
int f(int a, unsigned b) { return a < b; }
