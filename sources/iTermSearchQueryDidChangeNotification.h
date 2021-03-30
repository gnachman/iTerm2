//
//  iTermSearchQueryDidChangeNotification.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import "iTermNotificationCenter.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermSearchQueryDidChangeNotification : iTermBaseNotification
@property(nonatomic, strong, nullable)  id sender;

+ (instancetype)notificationWithSender:(id _Nullable)sender;
+ (void)subscribe:(NSObject *)owner block:(void (^)(id sender))block;

@end

NS_ASSUME_NONNULL_END
