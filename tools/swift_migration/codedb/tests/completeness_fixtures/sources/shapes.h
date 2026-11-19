// Fixture: the classes and types the completeness fixtures need, so that no
// SDK is needed.
typedef signed char BOOL;
typedef unsigned long NSUInteger;
typedef struct { double x, y; } SPoint;
typedef struct { SPoint origin; SPoint size; } SRect;
typedef struct { NSUInteger location, length; } SRange;
typedef float sfloat4 __attribute__((ext_vector_type(4)));
typedef union { SPoint p; double d[2]; } SUnion;
typedef struct { struct { SPoint inner; int k; }; int z; } SAnon;
typedef struct { SPoint c; int n; } Outer;
typedef struct { Outer o; } Nest;
__attribute__((objc_root_class))
@interface Shape {
    Class isa;
}
+ (instancetype)alloc;
- (instancetype)init;
- (id)objectAtIndexedSubscript:(NSUInteger)i;
- (void)setObject:(id)o atIndexedSubscript:(NSUInteger)i;
- (NSUInteger)countByEnumeratingWithState:(void *)state objects:(id *)buffer count:(NSUInteger)len;
@property (nonatomic) SPoint sv;
@property (nonatomic) SRect rect;
@property (nonatomic) SRange range;
@property (nonatomic) sfloat4 vec;
@property (nonatomic) int iv;
@property (nonatomic) NSUInteger length;
@property (nonatomic, strong) Shape *other;
- (SPoint)explicitPoint;
- (int)count;
- (int)a;
- (int)b;
- (id)lock;
@end
