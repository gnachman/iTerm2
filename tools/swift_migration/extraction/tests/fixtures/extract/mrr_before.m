// The before version of mrr_broken.m (manual reference counting).
#define nil ((id)0)
void consume(id);

__attribute__((objc_root_class))
@interface Base2
- (instancetype)init;
@end

@interface Holder : Base2
@end

@implementation Holder
- (instancetype)initCommon {
    // init_self{
    self = [super init];
    if (self) {
        consume(self);
    }
    // init_self}
    return self;
}
@end
