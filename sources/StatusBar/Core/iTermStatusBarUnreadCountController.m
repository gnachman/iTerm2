//
//  iTermStatusBarUnreadCountController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/6/19.
//

#import "iTermStatusBarUnreadCountController.h"
#import "iTermTuple.h"

NSString *const iTermStatusBarUnreadCountDidChange = @"iTermStatusBarUnreadCountDidChange";

@implementation iTermStatusBarUnreadCountController {
    NSMutableDictionary<iTermTuple<NSString *, NSString *> *, NSNumber *> *_sessionAndIdentifierToCount;
    NSMutableDictionary<NSString *, NSNumber *> *_identifierToCount;
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
        _sessionAndIdentifierToCount = [NSMutableDictionary dictionary];
        _identifierToCount = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setUnreadCountForComponentWithIdentifier:(NSString *)identifier
                                           count:(NSInteger)count {
    _identifierToCount[identifier] = @(count);
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermStatusBarUnreadCountDidChange
                                                        object:identifier];
}

- (void)setUnreadCountForComponentWithIdentifier:(NSString *)identifier
                                           count:(NSInteger)count
                                       sessionID:(NSString *)sessionID {
    _sessionAndIdentifierToCount[[iTermTuple tupleWithObject:sessionID andObject:identifier]] = @(count);
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermStatusBarUnreadCountDidChange
                                                        object:identifier];
}

- (NSInteger)unreadCountForComponentWithIdentifier:(NSString *)identifier
                                         sessionID:(NSString *)sessionID {
    NSNumber *number = _sessionAndIdentifierToCount[[iTermTuple tupleWithObject:sessionID andObject:identifier]];
    if (number) {
        return [number integerValue];
    }

    number = _identifierToCount[identifier];
    return [number integerValue];
}

@end
