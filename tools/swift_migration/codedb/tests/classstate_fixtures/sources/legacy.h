// Fixture: Legacy's interface, read by its own unit (manual reference counting) and by peer.m (ARC).
#import "cs_base.h"
#define NONATOMIC nonatomic
@interface Legacy : Root {
@public
    id _shared;
}
@property (NONATOMIC) int level;
@end
