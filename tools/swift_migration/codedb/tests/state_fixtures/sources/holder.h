// Fixture: a class whose header declares ivars. Line numbers are part of the expectations.
#import "state_base.h"
extern int gHolderCount;
extern NSString *const kExported;
static const int kHeaderLimit = 4;
@interface Holder : Root {
    id _plain;
    __weak id _weakRef;
@public
    int _publicCount;
@package
    Rect2 _rect;
@protected
    int _count;
    unsigned _flag : 1;
    IBOutlet id _outlet;
@private
    id<Drawing> _drawer;
    void (^_handler)(void);
    char *_cursor;
    int _buf[4];
    _Atomic int _atomicCount;
    Number2 _number;
    Class _cls;
}
@property (nonatomic, copy) NSString *title;
@property (nonatomic, weak) id delegate;
@property (atomic, readonly) int renamed;
@property (nonatomic, assign) int other;
- (void)run:(Holder *)peer;
@end
