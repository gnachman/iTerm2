// Fixture: sends in the size expression of a variable-length array
// (test_codedb_completeness.py). Every send in this file is listed there.
#import "shapes.h"
void useBuffer(void *p);
@implementation Shape (VLA)
- (void)arrays:(Shape *)x {
    int a[[x count]];
    unsigned short b[x.length];
    char c[x.other.length];
    typedef int Row[x.iv];
    Row r;
    useBuffer(a); useBuffer(b); useBuffer(c); useBuffer(r);
}
@end
