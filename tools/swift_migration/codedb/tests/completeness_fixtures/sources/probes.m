// Fixture: shapes of the AST that the default traversal skips or visits in
// one form only (test_codedb_completeness.py, ProbeTest). Each shape sends
// its own selector.
#import "probe_base.h"
typedef struct { PPoint c; int n; } OP;
typedef struct { PRect c; } ORect;
typedef struct { PRange c; } ORange;
typedef struct { pfloat4 c; } OVec;
typedef struct { PGridSize c; } OGrid;
typedef struct { OP c; } ONest;
typedef struct { void (^b)(void); int n; } OBlock;
void use(OP o);
void useV(void *p);
void cleanupF(int *p);
extern P *gp;

@implementation P
- (void)desig:(P *)x cond:(int)cond {
    OP a = {.c = x.r05};
    PPoint arr[1] = {[0] = x.r06};
    OP b = {.c = (x.r07)};
    OP c = (OP){.c = x.r08};
    OP d = {.c = x.other.r09};
    ORect e = {.c = x.r01};
    ORange f = {.c = x.r02};
    OVec g = {.c = x.r03};
    OGrid h = {.c = x.r04};
    PUnion u = {.p = x.r10};
    PAnon an = {.inner = x.r11, .z = 1};
    PPoint arr2[4] = {[0 ... 3] = {1, 2}};
    use((OP){.c = x.r14});
    PPoint a3[] = {x.r15};
    OP t = {.c = cond ? x.r16 : x.r17};
    OP cst = {.c = (PPoint)x.r18};
    OP ovr = {.c = x.r19, .c = x.r20};
    ONest nn = {.c = {.n = x.i06}};
    ONest np = {.c.n = x.i07};
    OP ex = {.c = [x s01]};
    OBlock ob = {.b = ^{ [x m08]; }, .n = x.i08};
    useV(&a); useV(arr); useV(&b); useV(&c); useV(&d); useV(&e); useV(&f); useV(&g); useV(&h); useV(&u);
    useV(&an); useV(arr2); useV(a3); useV(&t); useV(&cst); useV(&ovr); useV(&nn); useV(&np); useV(&ex); useV(&ob);
}
- (OP)ret:(P *)x { return (OP){.c = x.r13}; }
- (void)vla:(P *)x {
    int buf[[x m01]];
    char ch[x.i01];
    typeof(char[[x m03]]) tt;
    unsigned long sz = sizeof(int[[x m05]]);
    unsigned long sz2 = sizeof([x m06]);
    const char *enc = @encode(typeof([x m09]));
    __typeof__(buf) tb;
    _Atomic(int) at = [x m07];
    useV(buf); useV(ch); useV(tt); useV(&sz); useV(&sz2); useV(&enc); useV(tb); useV(&at);
}
static void vlaParam(P *x, int a[[x m02]]) { useV(a); }
- (void)callVlaParam:(P *)x { int z[1]; vlaParam(x, z); }
- (void)objcStmts:(P *)x {
    if (@available(macOS 13, *)) { [x m10]; }
    @synchronized([x o01]) { [x m11]; }
    @try { [x m12]; } @catch (id e) { [x m13]; } @finally { [x m14]; }
    @autoreleasepool { [x m15]; }
    for (id o in [x o02]) { [x m16]; }
    switch ([x m17]) { case 1: ({ [x m18]; }); break; }
    static id sv;
    void (^blk)(void) = ^{ sv = [x o03]; };
    blk();
    int ce = __builtin_choose_expr(1, [x m20], [x m21]);
    int ge = _Generic(0, int: [x m22], default: [x m23]);
    int bc = [x m24] ?: 5;
    id z = [x o04] ?: [x o05];
    __attribute__((cleanup(cleanupF))) int cl = x.i09;
    useV(&ce); useV(&ge); useV(&bc); useV((__bridge void *)z); useV(&cl);
}
- (int)unevaluatedIvars {
    int a = __builtin_choose_expr(0, _i14, 1);
    int b = _Generic(1, int: 2, default: _i15);
    int c = _Generic(_i16, int: 3, default: 4);
    return a + b + c;
}
- (void)pseudo:(P *)x {
    x.i02 += 1;
    x.i03++;
    ++x.i10;
    x.other.i04 = 5;
    x.other.i05 += 2;
    x[0] = x;
    id q = x[1];
    x[q] = x[q];
    int v = (x.i11 = 3);
    x.other.other.i12 = x.other.i13;
    x.r05 = x.other.r06;
    useV((__bridge void *)q); useV(&v);
}
@end
