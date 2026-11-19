// Fixture: the classes the cross-check fixtures need, so that no SDK is needed.
typedef signed char BOOL;
__attribute__((objc_root_class))
@interface CRoot {
    Class isa;
}
+ (instancetype)alloc;
+ (instancetype)new;
- (instancetype)init;
- (void)dealloc;
- (Class)class;
- (BOOL)isKindOfClass:(Class)c;
- (BOOL)respondsToSelector:(SEL)s;
- (instancetype)retain;
- (void)release;
- (instancetype)autorelease;
- (void)poke;
@end
@interface NSNumber : CRoot
+ (NSNumber *)numberWithInt:(int)v;
@end
@interface NSArray : CRoot
+ (instancetype)arrayWithObjects:(const id[])objects count:(unsigned long)count;
- (unsigned long)countByEnumeratingWithState:(void *)state objects:(id *)buffer count:(unsigned long)len;
@end
@interface NSString : CRoot
@end
@interface CRoot (Unused)
- (void)unusedHelperSelector;
@end
// Not called by any unit: the compiler emits no code for it.
static inline void UnusedHelper(CRoot *r) {
    [r unusedHelperSelector];
}
