// Fixture: the forms of a constant condition in Objective-C++
// (test_codedb_completeness.py, ConstantFormsTest). Each form sends its own
// selectors; the test compiles this file and checks every mark against the
// object's call sites.
#import "cf_base.h"
struct Box {
    Box(int v);
    Box(const Box &other);
    ~Box();
    int v;
};
int use(int v);
@interface CF (Boxes)
- (Box *)x1;
- (Box *)x2;
@end
constexpr bool kOff = false;

// Marked: the skipped arm of an if whose condition folds.
void IfConstexprVariable(CF *o) { if (kOff) [o k01]; }
void IfConstexpr(CF *o) { if constexpr (kOff) [o k02]; else [o k03]; }
void IfConstBool(CF *o) { const bool debug = false; if (debug) [o k04]; }

// The conditional operator and && and || as a scalar rvalue.
void ScalarConditional(CF *o) { int v = 0 ? [o i1] : [o i2]; use(v); }
void ScalarAnd(CF *o) { bool v = false && [o b1]; use(v); }
void ScalarOr(CF *o) { bool v = true || [o b2]; use(v); }
void ObjectConditional(CF *o) { id v = 0 ? [o o1] : [o o2]; (void)v; }

// Branch conditions, converted to bool.
void ConditionalInIf(CF *o) { if (0 ? [o b3] : [o b4]) [o k05]; }
void AndInIf(CF *o) { if ([o b5] && (false && [o b6])) [o k06]; }

// Lvalue conditionals and class-type operands.
void LvalueConditional(CF *o) { (0 ? *[o l1] : *[o l2]) = 3; }
void ReferenceConditional(CF *o) { int &r = 0 ? *[o l1] : *[o l2]; use(r); }
void MemberOfLvalue(CF *o) { use((int)(0 ? *[o l3] : *[o l4]).x); }
void RecordLvalueCopy(CF *o) { CFPair p = 0 ? *[o l5] : *[o l6]; use((int)p.x); }
void ClassLvalueCopy(CF *o) { Box b = 0 ? *[o x1] : *[o x2]; use(b.v); }
void ClassConditional(CF *o) { Box b = 0 ? Box([o i4]) : Box([o i5]); use(b.v); }
void ClassTemporary(CF *o) { use((0 ? Box([o i6]) : Box([o i7])).v); }
void LambdaConditional(CF *o) { auto f = [o] { return 0 ? [o i8] : [o i9]; }; use(f()); }
