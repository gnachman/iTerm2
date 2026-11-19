// Fixture: a class whose state classstate reports. Line numbers are part of the expectations.
#import "cs_base.h"
@interface Owner : Root <Drawing> {
@public
    int _pub;
@package
    int _pkg;
}
@property (nonatomic) int count;
@property (atomic) int total;
@property (nonatomic, readonly) int flag;
@property (nonatomic, readonly) Thing *name;
@end
@interface Owner () {
    PlainEnum _plain;
}
@end
