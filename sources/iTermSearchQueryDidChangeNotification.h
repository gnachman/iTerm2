//
//  iTermSearchQueryDidChangeNotification.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import "iTermNotificationCenter.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermSearchQueryDidChangeNotification : iTermBaseNotification

+ (instancetype)notification;
+ (void)subscribe:(NSObject *)owner block:(void (^)(void))block;

@end

NS_ASSUME_NONNULL_END
