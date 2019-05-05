//
//  iTermSecureKeyboardEntryController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 02/05/19.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermDidToggleSecureInputNotification;

@interface iTermSecureKeyboardEntryController : NSObject

@property (nonatomic, getter=isDesired) BOOL desired;
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;

+ (instancetype)sharedInstance;

- (void)toggle;
- (void)didStealFocus;
- (void)didReleaseFocus;

@end

NS_ASSUME_NONNULL_END
