//
//  iTermFlagsChangedNotification.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import "iTermNotificationCenter.h"

NS_ASSUME_NONNULL_BEGIN

@class NSEvent;

@interface iTermFlagsChangedNotification : iTermBaseNotification

@property (nonatomic, strong, readonly) NSEvent *event;

+ (instancetype)notificationWithEvent:(NSEvent *)event;
+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermFlagsChangedNotification * _Nonnull notification))block;
@end

NS_ASSUME_NONNULL_END
