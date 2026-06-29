//
//  iTermFlagsChangedNotification.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import "iTermFlagsChangedNotification.h"
#import "iTermNotificationCenter+Protected.h"

@interface iTermFlagsChangedNotification()
@property (nonatomic, strong, readwrite) NSEvent *event;
@end

@implementation iTermFlagsChangedNotification

+ (instancetype)notificationWithEvent:(id)event {
    iTermFlagsChangedNotification *notif = [[self alloc] initPrivate];
    notif.event = event;
    return notif;
}

+ (void)subscribe:(NSObject *)owner block:(void (^)(iTermFlagsChangedNotification * _Nonnull))block {
    [self internalSubscribe:owner withBlock:block];
}

@end
