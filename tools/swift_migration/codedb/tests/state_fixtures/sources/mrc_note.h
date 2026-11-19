// Fixture: classes compiled with manual reference counting whose header an ARC unit also reads. Line numbers are part of the expectations.
#import "state_base.h"
@interface Root (ManualCounting)
- (id)retain;
- (oneway void)release;
- (id)autorelease;
- (id)copy;
@end
@interface MrcNote : Root {
    id _kept;
    id _button;
    id _copied;
    int _size;
    id _title;
}
@property (nonatomic, retain) id title;
- (void)setUp:(id)b;
@end
@interface Dual : Root {
    id _shared;
}
@end
