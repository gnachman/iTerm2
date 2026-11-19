// Fixture: branches that a constant condition skips
// (test_codedb_completeness.py, ConstantConditionTest).
#import "shapes.h"
static const int kStaticOff = 0;
enum { kEnumOff = 0 };
int gNotConst = 0;
void Conditions(Shape *x) {
    const int debug = 0;
    if (0) [x a];
    if (debug) [x b]; else [x count];
    if (kStaticOff) [x lock];
    if (kEnumOff) [x explicitPoint];
    while (0) { [x other]; }
    int r = 0 && [x iv];
    r += 1 || [x length];
    r += debug ? [x rect].size.x : 2;
    if (gNotConst) [x vec];
    if (!debug) [x range];
    if (1) {} else { [x init]; }
}
