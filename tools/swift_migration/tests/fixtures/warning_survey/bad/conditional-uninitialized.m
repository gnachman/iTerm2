// expect: -Wconditional-uninitialized
#import "iTermStrictWarnings.h"
int f(int n) { int x; for (int i = 0; i < n; i++) { x = i; } return x; }
