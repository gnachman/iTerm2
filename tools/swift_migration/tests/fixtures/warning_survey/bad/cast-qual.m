// expect: -Wcast-qual
#import "iTermStrictWarnings.h"
char *f(const char *s) { return (char *)s; }
