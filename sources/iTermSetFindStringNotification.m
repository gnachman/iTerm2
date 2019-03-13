//
//  iTermSetFindStringNotification.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/12/19.
//

#import "iTermSetFindStringNotification.h"
#import "iTermNotificationCenter+Protected.h"

@implementation iTermSetFindStringNotification

+ (instancetype)notificationWithString:(NSString *)string {
    return [[self alloc] initWithString:string];
}

+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermSetFindStringNotification * _Nonnull))block {
    [self internalSubscribe:owner withBlock:block];
}

- (instancetype)initWithString:(NSString *)string {
    self = [super initPrivate];
    if (self) {
        _string = [string copy];
    }
    return self;
}

@end
