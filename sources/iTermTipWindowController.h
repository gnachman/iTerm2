//
//  iTermWelcomeWindowController.h
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import <Cocoa/Cocoa.h>

@protocol iTermTipWindowDelegate<NSObject>
- (void)tipWindowDismissed;
- (void)tipWindowPostponed;
- (void)tipWindowRequestsDisable;
@end

@interface iTermTipWindowController : NSWindowController

@property(nonatomic, assign) id<iTermTipWindowDelegate> delegate;

- (instancetype)initWithTitle:(NSString *)title body:(NSString *)body url:(NSString *)url;

@end
