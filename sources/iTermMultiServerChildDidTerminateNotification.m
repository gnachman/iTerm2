//
//  iTermMultiServerChildDidTerminateNotification.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import "iTermMultiServerChildDidTerminateNotification.h"
#import "iTermNotificationCenter+Protected.h"

@interface iTermMultiServerChildDidTerminateNotification()
@property (nonatomic, readwrite) pid_t pid;
@property (nonatomic, readwrite) int terminationStatus;
@end

@implementation iTermMultiServerChildDidTerminateNotification

+ (instancetype)notificationWithProcessID:(pid_t)pid terminationStatus:(int)terminationStatus {
    iTermMultiServerChildDidTerminateNotification *notif = [[self alloc] initPrivate];
    notif.pid = pid;
    notif.terminationStatus = terminationStatus;
    return notif;
}

+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermMultiServerChildDidTerminateNotification * _Nonnull notification))block {
    [self internalSubscribe:owner withBlock:block];
}

@end
