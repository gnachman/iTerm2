//
//  iTermAPIConnectionIdentifierController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/20/18.
//

#import "iTermAPIConnectionIdentifierController.h"

@implementation iTermAPIConnectionIdentifierController {
    NSMutableDictionary<NSString *, NSString *> *_map;
    NSInteger _nextIdentifier;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _map = [NSMutableDictionary dictionary];
    }
    return self;
}

- (id)identifierForKey:(NSString *)key {
    id identifier = _map[key];
    if (!identifier) {
        identifier = [@(_nextIdentifier) stringValue];
        _map[key] = identifier;
        _nextIdentifier++;
    }
    return identifier;
}

@end
