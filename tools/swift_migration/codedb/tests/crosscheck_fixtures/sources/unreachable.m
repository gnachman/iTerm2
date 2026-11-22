// Fixture: sends in code that no path reaches, which the compiler does not
// emit (test_codedb_crosscheck.py, UnreachableCodeTest).
#import "cbase.h"
@interface CRoot (Unreachable)
- (int)onlyUnreachable;
- (int)alsoLive;
- (int)afterAssert;
@end
void Halt(void) __attribute__((noreturn));
#define CHECK(c) do { if (!(c)) { Halt(); } } while (0)
@interface Unreacher : CRoot
@end
@implementation Unreacher
- (int)run:(int)n {
    if (n) {
        return [self alsoLive];
        [self alsoLive];
    }
    return 0;
    [self onlyUnreachable];
}
- (int)check {
    CHECK(0);
    return [self afterAssert];
}
@end
