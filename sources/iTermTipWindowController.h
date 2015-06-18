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
- (void)tipWindowDismissed;
- (void)tipWindowPostponed;
- (void)tipWindowRequestsDisable;
- (iTermTip *)tipWindowTipAfterTipWithIdentifier:(NSString *)identifier;
- (void)tipWindowWillShowTipWithIdentifier:(NSString *)identifier;

@end

@interface iTermTipWindowController : NSWindowController

@property(nonatomic, assign) id<iTermTipWindowDelegate> delegate;

- (instancetype)initWithTip:(iTermTip *)tip;

@end
