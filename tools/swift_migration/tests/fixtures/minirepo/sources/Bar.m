#import "Bar.h"
#import "Hub.h"

@implementation Bar {
    NSInteger _count;
}

- (void)tick {
    _count += 1;
}

@end
