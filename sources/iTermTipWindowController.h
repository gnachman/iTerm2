//
//  iTermWelcomeWindowController.h
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import <Cocoa/Cocoa.h>

@class iTermTip;

@protocol iTermTipWindowDelegate<NSObject>

// User requested to dismiss the tip.
- (void)tipWindowDismissed;

// User requested to show the tip again later.
- (void)tipWindowPostponed;

// User requested to disable all tips.
- (void)tipWindowRequestsDisable;

// Get the tip with a named id.
- (iTermTip *)tipWindowTipAfterTipWithIdentifier:(NSString *)identifier;
- (iTermTip *)tipWindowTipBeforeTipWithIdentifier:(NSString *)identifier;

// Indicates that a named tip will show imminently.
- (void)tipWindowWillShowTipWithIdentifier:(NSString *)identifier;

@end

// Shows a tip of the day in a card onscreen.
@interface iTermTipWindowController : NSWindowController

@property(nonatomic, assign) id<iTermTipWindowDelegate> delegate;

- (instancetype)initWithTip:(iTermTip *)tip;

// Use this to present the window.
- (void)showTipWindow;

@end
