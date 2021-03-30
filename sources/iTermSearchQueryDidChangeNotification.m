//
//  iTermSearchQueryDidChangeNotification.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import "iTermSearchQueryDidChangeNotification.h"
#import "iTermNotificationCenter+Protected.h"

@implementation iTermSearchQueryDidChangeNotification

+ (instancetype)notificationWithSender:(id _Nullable)sender {
    iTermSearchQueryDidChangeNotification *notification = [[self alloc] initPrivate];
    notification.sender = sender;
    return notification;
}

+ (void)subscribe:(NSObject *)owner block:(void (^)(id))block {
    [self internalSubscribe:owner withBlock:^(id notification) {
        iTermSearchQueryDidChangeNotification *notif = notification;
        block(notif.sender);
    }];
}

@end
