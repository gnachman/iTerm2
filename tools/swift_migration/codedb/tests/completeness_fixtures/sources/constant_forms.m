// Fixture: the forms of a constant condition, for which the extractor sets
// in_constant_false_branch only where the compiler emits nothing at -O0
// (test_codedb_completeness.py, ConstantFormsTest). Each form sends its own
// selectors; the test compiles this file and checks every mark against the
// object's call sites.
#import "cf_base.h"
static const BOOL kOff = 0;
enum { kEnumOff = 0 };
#define DEBUG_OFF 0
#define TWICE(x) (0 ? (x) : (x))
#define IS_SMALL(x) (sizeof(x) == sizeof(float) ? [o c1] : [o c2])
int gCount;
int use(int v);

// Marked: the skipped arm of an if whose condition folds.
void IfZero(CF *o) { if (0) [o k01]; }
void IfStaticConst(CF *o) { if (kOff) [o k02]; }
void IfConstLocal(CF *o) { const BOOL debug = 0; if (debug) [o k03]; else [o k04]; }
void IfEnum(CF *o) { if (kEnumOff) [o k05]; }
void IfMacro(CF *o) { if (DEBUG_OFF) { [o k06]; } }
void IfElse(CF *o) { if (1) {} else { [o k07]; } }
void IfNestedSwitch(CF *o, int n) { if (0) { switch (n) { case 1: [o k08]; break; } } }

// Not marked: the skipped arm holds a label that can be reached.
void IfGotoLabel(CF *o) { goto in; if (0) { in: [o k09]; } }
void IfCaseLabel(CF *o, int n) { switch (n) { case 0: if (0) { case 1: [o k10]; } break; } }

// The conditional operator and && and || as a scalar rvalue.
void ScalarConditional(CF *o) { int v = 0 ? [o i1] : [o i2]; use(v); }
void ScalarAnd(CF *o) { BOOL v = 0 && [o b1]; use(v); }
void ScalarOr(CF *o) { BOOL v = 1 || [o b2]; use(v); }
void ObjectConditional(CF *o) { id v = 1 ? [o o1] : [o o2]; (void)v; }
void ObjectAssign(CF *o) { id v = 0; v = 0 ? [o o3] : [o o4]; (void)v; }
id ObjectReturn(CF *o) { return 0 ? [o o5] : [o o6]; }
void IgnoredConditional(CF *o) { 0 ? [o i3] : [o i4]; }
void VoidConditional(CF *o) { 0 ? [o v1] : [o v2]; }
void ArgumentInCondition(CF *o) { if (use(0 ? [o i5] : [o i6])) [o k11]; }
void ScalarAndOfAnd(CF *o) { BOOL v = (0 && [o b3]) && [o b4]; use(v); }

// Branch conditions: CodeGen emits both arms.
void ConditionalInIf(CF *o) { if (0 ? [o b5] : [o b6]) [o k12]; }
void AndInIf(CF *o) { if ([o b7] && (0 && [o b8])) [o k13]; }
void NotConditionalInWhile(CF *o) { while (!(1 ? [o b9] : [o c3])) break; }
void MacroConditionalInIf(CF *o) { if (!IS_SMALL(o.d1)) [o k14]; }
void ConditionalOfConditional(CF *o) { int v = (0 ? [o c4] : [o c5]) ? 1 : 2; use(v); }
void OrInFor(CF *o) { for (; [o c6] || (1 || [o c7]);) break; }
void LabelInDeadOperand(CF *o) { int v = 0 ? ({ goto in; in: [o i7]; }) : [o i8]; use(v); }

// Other emitters: an aggregate, a complex number. (A conditional is an lvalue
// only in C++: constant_forms.mm.)
void AggregateConditional(CF *o) { CFPair p = 0 ? [o p1] : [o p2]; use((int)p.x); }
void ComplexConditional(CF *o) { _Complex double z = 0 ? [o z1] : [o z2]; use((int)__real__ z); }
void PointerConditional(CF *o) { *(0 ? [o l1] : [o l2]) = 3; }
void MemberOfConditional(CF *o) { use((int)(0 ? *[o l3] : *[o l4]).x); }
void GnuConditional(CF *o) { use(0 ?: [o g1]); use([o g2] ?: [o g3]); }

@implementation CF (Forms)
// One reference row for a macro argument expanded into a dead and a live arm.
- (int)twiceIvar { return TWICE(_count); }
- (int)twiceStatic { return TWICE(gCount); }
- (int)deadIvar { if (0) return _count; return 0; }
- (int)twiceSend { return TWICE([self s1]) + [self s2]; }
@end
