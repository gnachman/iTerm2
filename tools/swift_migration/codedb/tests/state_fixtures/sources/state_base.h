// Fixture: a root class and the runtime pieces the state fixtures use, so that no SDK is needed.
__attribute__((objc_root_class))
@interface Root
+ (instancetype)alloc;
- (instancetype)init;
- (Class)class;
@end
@interface NSString : Root
@end
@protocol Drawing
- (void)draw;
@end
typedef long dispatch_once_t;
// As the SDK declares it: a macro for an inline function.
void _dispatch_once(dispatch_once_t *predicate, void (^block)(void));
#define dispatch_once _dispatch_once
#define IBOutlet __attribute__((iboutlet))
typedef struct { double x, y; } Point2;
typedef struct { Point2 origin; double width, height; } Rect2;
typedef union { int i; float f; } Number2;
typedef struct { id obj; int n; } Boxed2;
typedef float Vec4 __attribute__((ext_vector_type(4)));
