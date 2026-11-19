// Fixture: the extractor bug the cross-check found (test_codedb_crosscheck.py,
// ExtractorBugTest): a dot-syntax getter of struct type directly under a
// designated initializer was not recorded as a send. Fixed: the cross-check
// finds no difference. Line numbers are not part of the expectations.
#import "cbase.h"
typedef struct { double w, h; } CSize;
typedef struct { CSize size; int n; } CBox;
@interface Boxer : CRoot
@property (nonatomic) CSize size;
@property (nonatomic) CSize origin;
@end
@implementation Boxer
// The getter origin is sent only here: a set difference.
- (CBox)onlySite {
    CBox b = { .size = self.origin, .n = 1 };
    return b;
}
// The getter size is sent here twice, once under the designated
// initializer: a difference of call-site counts only.
- (CBox)twoSites {
    CSize s = self.size;
    CBox b = { .size = self.size, .n = 2 };
    b.n += (int)s.w;
    return b;
}
@end
