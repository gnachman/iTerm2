// Fixture: Objective-C++ shapes (test_codedb_completeness.py, ProbeTest).
#import "probe_base.h"
extern P *gp;
void useV(void *p);
struct DefMember {
    int a = [gp m01];
    int b;
    DefMember() : b([gp m02]) {}
    DefMember(int) : a(0), b([gp m03]) {}
};
struct Agg { PPoint c; int n; };
static int defArg(int v = [gp m04]) { return v; }
template <typename T> int tmpl(T *x) { return [x m05]; }
template <typename T> int tmplProp(T *x) { return x.i01; }
template <typename T> int tmplNonDep(T v) { return [gp m06] + (int)v; }
template <typename T> struct TS { int f() { return [gp m07]; } };
template <typename T> struct TU { int g() { return [gp m08]; } };  // never instantiated
struct Inl { int unused() { return [gp m09]; } int used() { return [gp m10]; } };
@interface Q : P @end
@implementation P
- (void)cxx:(P *)x {
    DefMember d1;
    DefMember d2(1);
    int da = defArg() + defArg();
    int t = tmpl(x) + tmpl((Q *)x) + tmplProp(x) + tmplNonDep(1) + tmplNonDep(1.0);
    TS<int> ts; t += ts.f();
    TS<char> ts2; t += ts2.f();
    auto lam = [v = [x m11]]() { return v; };
    t += lam();
    auto lam2 = [x]() { return [x m12]; };
    t += lam2();
    const PPoint &ref = x.r05;
    Agg ag = {.c = x.r06, .n = 1};
    Agg ag2{x.r07, 2};
    Inl in; t += in.used();
    useV(&d1); useV(&d2); useV(&da); useV(&t); useV((void *)&ref); useV(&ag); useV(&ag2);
}
@end
