// Fixture: a root class and the types the class state fixtures use, so that no SDK is needed.
__attribute__((objc_root_class))
@interface Root
+ (instancetype)alloc;
- (instancetype)init;
@end
@interface Thing : Root
@end
@protocol Drawing
- (void)draw;
@end
typedef enum { PlainA, PlainB } PlainEnum;
typedef enum __attribute__((enum_extensibility(open))) NiceEnum : long { NiceA, NiceB } NiceEnum;
typedef struct { id obj; int n; } StrongBox;
typedef struct { __unsafe_unretained id obj; int n; } UnretainedBox;
typedef struct { int n; char tail[]; } Flex;
typedef union { int i; float f; } Number;
typedef struct Opaque Opaque;
typedef int (*Callback)(int);
typedef int (*VarCallback)(int, ...);
typedef float Vec4 __attribute__((ext_vector_type(4)));
void Fill(int *p);
// Accessor-shaped methods that subclasses inherit: -pub for Owner's _pub,
// and custom getter names for LegacyHolder's _lit and _depth.
@interface Root (Naming)
- (int)pub;
@property (nonatomic, readonly, getter=isLit) signed char lit;
@property (nonatomic, readonly, getter=currentDepth) int depth;
@end
