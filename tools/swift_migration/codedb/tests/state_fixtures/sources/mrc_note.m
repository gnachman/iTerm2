// Fixture: the @implementation of mrc_note.h, compiled with manual reference counting. Line numbers are part of the expectations.
#import "mrc_note.h"
@implementation MrcNote
@synthesize title = _title;
- (void)setUp:(id)b {
    _kept = [b retain];
    _button = b;
    _copied = [b copy];
    _size = 1;
    [_kept release];
}
- (void)tearDown {
    [_kept release];
    [_copied autorelease];
    _kept = [[Root alloc] init];
}
@end
@implementation Dual
- (void)touch {
    _shared = 0;
}
@end
