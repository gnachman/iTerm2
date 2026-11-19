// Fixture: sends in branches that a constant condition skips, which the
// compiler does not emit (test_codedb_crosscheck.py, ConstantFalseTest).
#import "cbase.h"
@interface CRoot (Constant)
- (int)onlyDead;
- (int)alsoLive;
- (int)shortCircuit;
- (int)ternaryDead;
- (int)whileBody;
@end
static const BOOL kDebug = 0;
static int gCounter;
@interface Constanter : CRoot
@end
@implementation Constanter {
    int _hits;
}
- (int)run {
    const BOOL debug = 0;
    int r = 0;
    if (debug) {
        r += [self onlyDead];
        _hits++;
        gCounter++;
    }
    if (kDebug) r += [self alsoLive];
    r += [self alsoLive];
    r += 0 && [self shortCircuit];
    r += debug ? [self ternaryDead] : 1;
    while (0) {
        r += [self whileBody];
    }
    return r;
}
@end
