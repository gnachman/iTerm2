#import "Owner.h"

@interface OwnerBadge : NSView
@end

@implementation OwnerBadge
@end

@implementation OwnerController {
    NSNib *_nib;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _nib = [[NSNib alloc] initWithNibNamed:@"Owner" bundle:nil];
    }
    return self;
}

- (id)copyTitle {
    return nil;
}

- (void)press:(id)sender {
}

- (void)fixtureZoom:(id)sender {
}

- (NSUInteger)countOfItems {
    return 0;
}

- (id)objectInItemsAtIndex:(NSUInteger)index {
    return nil;
}

@end
