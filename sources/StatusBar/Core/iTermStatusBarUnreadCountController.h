//
//  iTermStatusBarUnreadCountController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/6/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermStatusBarUnreadCountDidChange;

@interface iTermStatusBarUnreadCountController : NSObject

+ (instancetype)sharedInstance;

- (void)setUnreadCountForComponentWithIdentifier:(NSString *)identifier
                                           count:(NSInteger)count;

- (void)setUnreadCountForComponentWithIdentifier:(NSString *)identifier
                                           count:(NSInteger)count
                                       sessionID:(NSString *)sessionID;

- (NSInteger)unreadCountForComponentWithIdentifier:(NSString *)identifier
                                         sessionID:(NSString *)sessionID;

@end

NS_ASSUME_NONNULL_END
