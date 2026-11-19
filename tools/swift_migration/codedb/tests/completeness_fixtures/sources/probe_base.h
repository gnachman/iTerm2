// Fixture: the declarations of the probe fixtures (test_codedb_completeness.py).
typedef signed char BOOL;
typedef unsigned long NSUInteger;
typedef struct { double x, y; } PPoint;
typedef struct { PPoint origin; PPoint size; } PRect;
typedef struct { NSUInteger location, length; } PRange;
typedef float pfloat4 __attribute__((ext_vector_type(4)));
typedef struct { int w, h; } PGridSize;
typedef union { PPoint p; double d[2]; } PUnion;
typedef struct { struct { PPoint inner; int k; }; int z; } PAnon;
__attribute__((objc_root_class))
@interface PRoot { Class isa; }
+ (instancetype)alloc;
- (instancetype)init;
- (id)objectAtIndexedSubscript:(NSUInteger)i;
- (void)setObject:(id)o atIndexedSubscript:(NSUInteger)i;
- (id)objectForKeyedSubscript:(id)k;
- (void)setObject:(id)o forKeyedSubscript:(id)k;
- (NSUInteger)countByEnumeratingWithState:(void *)state objects:(id *)buffer count:(NSUInteger)len;
@end
@interface P : PRoot
@property (nonatomic) PRect r01; @property (nonatomic) PRange r02; @property (nonatomic) pfloat4 r03;
@property (nonatomic) PGridSize r04; @property (nonatomic) PPoint r05; @property (nonatomic) PPoint r06;
@property (nonatomic) PPoint r07; @property (nonatomic) PPoint r08; @property (nonatomic, strong) P *other;
@property (nonatomic) PPoint r09; @property (nonatomic) PPoint r10; @property (nonatomic) PPoint r11;
@property (nonatomic) PPoint r12; @property (nonatomic) PPoint r13; @property (nonatomic) PPoint r14;
@property (nonatomic) PPoint r15; @property (nonatomic) PPoint r16; @property (nonatomic) PPoint r17;
@property (nonatomic) PPoint r18; @property (nonatomic) PPoint r19; @property (nonatomic) PPoint r20;
@property (nonatomic) int i01; @property (nonatomic) int i02; @property (nonatomic) int i03;
@property (nonatomic) int i04; @property (nonatomic) int i05; @property (nonatomic) int i06;
@property (nonatomic) int i07; @property (nonatomic) int i08; @property (nonatomic) int i09;
@property (nonatomic) int i10; @property (nonatomic) int i11; @property (nonatomic) int i12;
@property (nonatomic) int i13; @property (nonatomic) int i14; @property (nonatomic) int i15;
@property (nonatomic) int i16; @property (nonatomic) int i17; @property (nonatomic) int i18;
@property (nonatomic) int i19; @property (nonatomic) int i20; @property (nonatomic) int i21;
@property (nonatomic) int i22; @property (nonatomic) int i23; @property (nonatomic) int i24;
@property (nonatomic) int i25; @property (nonatomic) int i26; @property (nonatomic) int i27;
@property (nonatomic) int i28; @property (nonatomic) int i29; @property (nonatomic) int i30;
- (int)m01; - (int)m02; - (int)m03; - (int)m04; - (int)m05; - (int)m06; - (int)m07; - (int)m08;
- (int)m09; - (int)m10; - (int)m11; - (int)m12; - (int)m13; - (int)m14; - (int)m15; - (int)m16;
- (int)m17; - (int)m18; - (int)m19; - (int)m20; - (int)m21; - (int)m22; - (int)m23; - (int)m24;
- (id)o01; - (id)o02; - (id)o03; - (id)o04; - (id)o05;
- (PPoint)s01; - (PPoint)s02;
@end
