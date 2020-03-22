//
//  iTermMultiServerChildDidTerminateNotification.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import "iTermNotificationCenter.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermMultiServerChildDidTerminateNotification : iTermBaseNotification

@property (nonatomic, readonly) pid_t pid;
@property (nonatomic, readonly) int terminationStatus;

+ (instancetype)notificationWithProcessID:(pid_t)pid terminationStatus:(int)terminationStatus;
+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermMultiServerChildDidTerminateNotification * _Nonnull notification))block;
@end

NS_ASSUME_NONNULL_END
