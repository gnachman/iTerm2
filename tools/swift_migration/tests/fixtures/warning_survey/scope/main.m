#import "before.h"
#import "iTermStrictWarnings.h"
#import "after.h"

int expanded(long x) { int y; ASSIGN_NARROW(y, x); return y; }
int direct(long x) { return x; }
