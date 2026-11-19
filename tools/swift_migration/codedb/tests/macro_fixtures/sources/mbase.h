// Fixture: a header with an include guard. Line numbers are part of the expectations.
#ifndef MBASE_H
#define MBASE_H
__attribute__((objc_root_class))
@interface MRoot
+ (instancetype)alloc;
- (instancetype)init;
- (void)log:(const char *)text;
- (id)lockObject;
- (void)ping;
@end
@interface NSString : MRoot
@end
#define nil ((id)0)
#endif  // MBASE_H
