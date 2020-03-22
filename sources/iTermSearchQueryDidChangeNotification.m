//
//  iTermSearchQueryDidChangeNotification.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import "iTermSearchQueryDidChangeNotification.h"
#import "iTermNotificationCenter+Protected.h"

@implementation iTermSearchQueryDidChangeNotification

+ (instancetype)notification {
    return [[self alloc] initPrivate];
}

+ (void)subscribe:(NSObject *)owner block:(void (^)(void))block {
    [self internalSubscribe:owner withBlock:^(id notification) {
        block();
    }];
}

@end
