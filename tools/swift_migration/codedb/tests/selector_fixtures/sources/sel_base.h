// Fixture: a root class and the runtime functions, so that no SDK is needed.
__attribute__((objc_root_class))
@interface Base
+ (instancetype)alloc;
- (Class)class;
+ (Class)class;
- (id)performSelector:(SEL)s;
- (id)performSelector:(SEL)s withObject:(id)o afterDelay:(double)d;
- (int)respondsToSelector:(SEL)s;
- (id)valueForKey:(id)key;
- (void)setValue:(id)v forKey:(id)key;
- (void)addObserver:(id)o forKeyPath:(id)k options:(int)opts context:(void *)c;
- (void)setAction:(SEL)s;
- (SEL)action;
@end
@interface NSString : Base
@end
SEL NSSelectorFromString(NSString *s);
Class NSClassFromString(NSString *s);
NSString *NSStringFromSelector(SEL s);
SEL sel_registerName(const char *s);
typedef struct objc_method *Method;
Method class_getInstanceMethod(Class c, SEL s);
void method_exchangeImplementations(Method a, Method b);
id objc_msgSend(id self, SEL op, ...);
