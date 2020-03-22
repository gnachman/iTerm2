//
//  iTermNotificationCenter.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/1/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermBaseNotification : NSObject
+ (void)subscribe:(NSObject *)owner selector:(SEL)selector;
- (nullable instancetype)init NS_UNAVAILABLE;
- (void)post;
@end

NS_ASSUME_NONNULL_END
