#import "Multi.h"

#define WEAKLY_REFERENCEABLE - (id)weakSelf { return self; }

@interface Helper : NSObject
@end

@implementation Helper {
    int _shared;
    NSMutableArray *_items;
}

- (void)touch {
    _shared = 1;
    [_items removeAllObjects];
}

@end

@interface Old : NSObject {
    NSString *name_;
    int age_;
}
@property (nonatomic, copy) NSString *name;
@end

@implementation Old
@synthesize name = name_;

- (int)age {
    return age_;
}
@end

@implementation Multi {
    int _shared;
    NSInteger _count;
    NSMutableArray *_items;
    NSObject *_lock;
}

@synthesize label = _label;
@dynamic gone;

WEAKLY_REFERENCEABLE

- (void)dealloc {
    _shared = 0;
}

- (NSInteger)count {
    return _count;
}

- (void)setCount:(NSInteger)count {
    _count = MAX(0, count);
}

- (void)work {
    @synchronized (_lock) {
        _shared += 1;
    }
    _autoProp = nil;
    _label = @"x";
}

@end
