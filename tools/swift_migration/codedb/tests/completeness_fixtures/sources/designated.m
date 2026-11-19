// Fixture: property getters of structure and vector type written directly
// as the value of a designator (test_codedb_completeness.py). Every send in
// this file is listed there.
#import "shapes.h"
typedef struct { SRect r; } ORect;
typedef struct { SRange r; } ORange;
typedef struct { sfloat4 v; } OVec;
void take(Outer o);
@implementation Shape (Designated)
- (void)designated:(Shape *)x {
    Outer a = {.c = x.sv};
    SPoint b[1] = {[0] = x.sv};
    Outer c = {.c = (x.sv)};
    Outer d = (Outer){.c = x.sv};
    Outer e = {.c = x.other.sv};
    ORect f = {.r = x.rect};
    ORange g = {.r = x.range};
    OVec h = {.v = x.vec};
    SUnion u = {.p = x.sv};
    SAnon an = {.inner = x.sv, .z = 1};
    take((Outer){.c = x.sv});
    Outer over = {.c = x.rect.origin, .c = x.sv};
}
- (void)controls:(Shape *)x {
    Outer a = {.c = x.sv, .n = x.iv};
    Outer b = {.c = [x explicitPoint]};
    SPoint c[1] = {x.sv};
    Nest d = {.o = {.n = x.iv}};
    Outer e = {.c = x.iv ? x.sv : x.sv};
}
@end
