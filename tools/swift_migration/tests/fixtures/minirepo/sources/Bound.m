#import "Bound.h"
@implementation Bound

@synthesize thing = _thing;

+ (NSSet *)keyPathsForValuesAffectingQuiet {
    return [NSSet set];
}

- (void)observe:(id)x {
    [x addObserver:self forKeyPath:@"watched" options:0 context:nil];
    [NSSortDescriptor sortDescriptorWithKey:@"sorted" ascending:YES];
}

@end
