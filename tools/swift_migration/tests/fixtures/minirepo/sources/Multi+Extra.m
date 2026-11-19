#import "Multi.h"

@implementation Multi (Extra)

- (void)extraWork {
    _shared = 2;
    NSLog(@"%ld", (long)_count);
}

@end
