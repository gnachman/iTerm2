// Fixture for the extractor tests. Line numbers are part of the expectations.
#import "helpers.h"
#define BLOCK(x) [^id() { return [self x]; } copy]
#define LOAD(n) [self load_##n]
#define TWICE(s) [self s]; [self s]

@implementation Widget
+ (instancetype)make { return 0; }
- (id)copy { return self; }
- (void)doThing {}
- (int)load_alpha { return 1; }
- (void)helperSend {}
- (Widget *)makeThing { return self; }
- (id)objectAtIndexedSubscript:(long)i { return self; }
- (int)title { return 0; }
- (void)setTitle:(int)t {}

- (void)run {
    [self doThing];
    id anything = self;
    [anything doThing];
    [Widget make];
    void (^b)(void) = ^{ [self doThing]; };
    b();
    BLOCK(makeThing);
    LOAD(alpha);
    TWICE(doThing);
    int t = [self makeThing].title;
    self.title = t;
    (void)self[0];
}
@end
