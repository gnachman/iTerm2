// Fixture: sends in always_inline functions, which the compiler emits once
// per call, next to a send in a branch that a constant condition skips
// (test_codedb_crosscheck.py, InlinedFunctionTest).
#import "cbase.h"
@interface CRoot (Inlined)
- (int)inInline;
- (int)deadAndInline;
- (int)tooMany;
@end
static inline __attribute__((always_inline)) int Twice(CRoot *o) {
    return [o inInline] + [o deadAndInline];
}
static inline __attribute__((always_inline)) int Outer(CRoot *o) {
    return Twice(o) + Twice(o);
}
@interface Inliner : CRoot
@end
@implementation Inliner
- (int)run {
    int r = Twice(self) + Twice(self) + Outer(self);
    if (0) r += [self deadAndInline];
    return r;
}
@end
