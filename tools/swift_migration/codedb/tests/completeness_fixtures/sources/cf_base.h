// Fixture: the declarations of constant_forms.m and constant_forms.mm
// (test_codedb_completeness.py, ConstantFormsTest).
typedef signed char BOOL;
typedef struct { double x, y; } CFPair;
__attribute__((objc_root_class))
@interface CF {
    Class isa;
    int _count;
}
- (int)i1; - (int)i2; - (int)i3; - (int)i4; - (int)i5; - (int)i6; - (int)i7; - (int)i8; - (int)i9;
- (id)o1; - (id)o2; - (id)o3; - (id)o4; - (id)o5; - (id)o6;
- (BOOL)b1; - (BOOL)b2; - (BOOL)b3; - (BOOL)b4; - (BOOL)b5; - (BOOL)b6; - (BOOL)b7; - (BOOL)b8; - (BOOL)b9;
- (BOOL)c1; - (BOOL)c2; - (BOOL)c3; - (BOOL)c4; - (BOOL)c5; - (BOOL)c6; - (BOOL)c7; - (BOOL)c8; - (BOOL)c9;
- (double)d1;
- (CFPair)p1; - (CFPair)p2;
- (_Complex double)z1; - (_Complex double)z2;
- (int *)l1; - (int *)l2; - (CFPair *)l3; - (CFPair *)l4; - (CFPair *)l5; - (CFPair *)l6;
- (void)v1; - (void)v2; - (void)v3; - (void)v4;
- (void)k01; - (void)k02; - (void)k03; - (void)k04; - (void)k05; - (void)k06; - (void)k07; - (void)k08;
- (void)k09; - (void)k10; - (void)k11; - (void)k12; - (void)k13; - (void)k14; - (void)k15; - (void)k16;
- (int)g1; - (int)g2; - (int)g3;
- (int)s1; - (int)s2;
@end
