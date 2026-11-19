// expect: -Wobjc-signed-char-bool-implicit-int-conversion
// arch: x86_64
// clean-on: arm64 (BOOL is bool there, so the conversion is a test against zero)
#import <objc/objc.h>
#import "iTermStrictWarnings.h"
BOOL f(int x) { BOOL b = x; return b; }
