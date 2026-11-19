#import "PidLeaf.h"

@implementation PidLeaf

- (void)run {
    @synchronized (self) {
        NSLog(@"run");
    }
}

@end
