#import "Family.h"
#import "Hub.h"

@implementation Parent

- (void)setDepth:(NSInteger)depth {
}

@end

@implementation Child {
    id _owner;
    NSString *_shout;
    NSInteger _depth;
    Base *_base;
    dispatch_queue_t _queue;
    os_log_t _log;
    FamilyBlock _block;
    iTermThing *_thing;
    unsigned int _bits : 2;
#if FAMILY_DEBUG
    int _debugCounter;
#endif
}

- (NSString *)computed {
    return @"x";
}

- (NSString *)shout {
    return [_shout uppercaseString];
}

- (NSData *)report:(int)code :(int)subcode {
    return nil;
}

static int ChildPeek(Child *child) {
    return (int)child->_depth;
}

@end
