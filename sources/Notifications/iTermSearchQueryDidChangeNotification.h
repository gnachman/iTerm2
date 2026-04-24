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
@property(nonatomic) BOOL internallyGenerated;

+ (instancetype)notificationWithSender:(id _Nullable)sender
                   internallyGenerated:(BOOL)internallyGenerated;
+ (void)subscribe:(NSObject *)owner block:(void (^)(id sender, BOOL internallyGenerated))block;

@end

NS_ASSUME_NONNULL_END
