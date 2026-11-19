// self is assigned only in the helper (manual reference counting).
#define nil ((id)0)
void consume(id);

__attribute__((objc_root_class))
@interface Base2
- (instancetype)init;
@end

@interface Holder : Base2
@end

@implementation Holder
- (void)commonHelper {
    // init_self{
    self = [super init];
    if (self) {
        consume(self);
    }
    // init_self}
}

- (instancetype)initCommon {
    [self commonHelper];
    return self;
}
@end
