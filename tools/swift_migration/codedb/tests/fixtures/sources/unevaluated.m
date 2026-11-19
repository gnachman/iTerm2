// Fixture: sends in unevaluated operands are not recorded; an operand of variably modified type is evaluated. Line numbers are part of the expectations.
#import "widget.h"
#define MAXW(a, b) ({ __typeof__(a) __a = (a); __typeof__(b) __b = (b); __a > __b ? __a : __b; })
void Unevaluated(Widget *w) {
    __typeof__([w makeThing]) x = [w makeThing];
    (void)sizeof([w makeThing]);
    (void)__alignof__([w makeThing]);
    (void)_Alignof(__typeof__([w makeThing]));
    (void)@encode(__typeof__([w makeThing]));
    int m = MAXW([w title], 2);
    (void)x; (void)m;
    (void)sizeof(int[[w other]]);
    __typeof__((int (*)[[w vm]])0) p2 = 0;
    __typeof__(*({int (*q)[[w gen]]=0;q;})) *p3 = 0;
    (void)p2; (void)p3;
}
