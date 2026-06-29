//
//  iTermSecureKeyboardEntryController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 02/05/19.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermDidToggleSecureInputNotification;

@protocol iTermSecureInputRequesting<NSObject>
- (BOOL)isRequestingSecureInput;
@end

@interface iTermSecureKeyboardEntryController : NSObject

@property (nonatomic, readonly) BOOL isDesired;
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly) BOOL enabledByUserDefault;

+ (instancetype)sharedInstance;

- (void)toggle;
- (void)didStealFocus;
- (void)didReleaseFocus;
- (void)update;
- (void)disableUntilDeactivated;

@end

NS_ASSUME_NONNULL_END
