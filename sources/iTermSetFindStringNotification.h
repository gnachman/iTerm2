//
//  iTermSetFindStringNotification.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/12/19.
//

#import "iTermNotificationCenter.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermSetFindStringNotification : iTermBaseNotification

@property (nonatomic, readonly) NSString *string;

+ (instancetype)notificationWithString:(NSString *)string;
+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermSetFindStringNotification * _Nonnull notification))block;

@end

NS_ASSUME_NONNULL_END
