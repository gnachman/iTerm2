//
//  iTermSearchQueryDidChangeNotification.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import "iTermSearchQueryDidChangeNotification.h"
#import "iTermNotificationCenter+Protected.h"

@implementation iTermSearchQueryDidChangeNotification

+ (instancetype)notificationWithSender:(id _Nullable)sender 
                   internallyGenerated:(BOOL)internallyGenerated {
    iTermSearchQueryDidChangeNotification *notification = [[self alloc] initPrivate];
    notification.sender = sender;
    notification.internallyGenerated = internallyGenerated;
    return notification;
}

+ (void)subscribe:(NSObject *)owner block:(void (^)(id, BOOL))block {
    [self internalSubscribe:owner withBlock:^(id notification) {
        iTermSearchQueryDidChangeNotification *notif = notification;
        block(notif.sender, notif.internallyGenerated);
    }];
}

@end
