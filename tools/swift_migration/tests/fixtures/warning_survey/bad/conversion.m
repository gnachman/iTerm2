// expect: -Wstring-conversion (a part of -Wconversion listed by no other line)
#import "iTermStrictWarnings.h"
int f(void) { if ("abc") { return 1; } return 0; }
