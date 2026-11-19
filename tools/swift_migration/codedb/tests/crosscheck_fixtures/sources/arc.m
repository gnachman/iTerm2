// Fixture: compiled with ARC. Line numbers are not part of the expectations.
#import "cbase.h"
@interface Thing : CRoot {
    id _strong;
    int _count;
}
@property (nonatomic, strong) id item;
- (void)direct __attribute__((objc_direct));
@end
// A direct method of a category: its symbol is -[Thing catDirect], without
// the category.
@interface Thing (Direct)
- (void)catDirect __attribute__((objc_direct));
@end
@implementation Thing
- (void)dealloc {
    _count = 0;
}
- (void)run {
    id a = @[ @1, self ];
    for (id x in a) {
        [x poke];
    }
    Thing *t = [[Thing alloc] init];
    if ([t isKindOfClass:[Thing class]] && [t respondsToSelector:@selector(run)]) {
        self.item = t;
    }
    [super poke];
    [self direct];
    [self catDirect];
    [t poke];
}
- (void)direct {
}
@end
@implementation Thing (Direct)
- (void)catDirect {
}
@end
@implementation Thing (Extra)
- (void)extra {
    [self run];
}
@end
