//
//  iTermUnobtrusiveMessage.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/11/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE_MAC(10_14)
@interface iTermUnobtrusiveMessage : NSView
- (instancetype)initWithMessage:(NSString *)message NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)animateFromTopRightWithCompletion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
