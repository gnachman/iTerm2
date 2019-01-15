//
//  iTermTipController.h
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import <Foundation/Foundation.h>

// Manages the tip of the day. NOTE: Only supports OS 10.10+. Will return a nil
// sharedInstance on older OSes.
@interface iTermTipController : NSObject

// Are we currently showing a tip?
@property(nonatomic, readonly) BOOL showingTip;

+ (instancetype)sharedInstance;

// Call this when the app finishes launching to show the initial card.
- (void)startWithPermissionPromptAllowed:(BOOL)permissionPromptAllowed notBefore:(NSDate *)notBeforeDate;

// Show the last-seen tip (or first, if there is no last-seen) immediately.
- (void)showTip;

- (BOOL)willAskPermission;

@end
