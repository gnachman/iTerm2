//
//  TmuxController.h
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import <Cocoa/Cocoa.h>
#import "TmuxGateway.h"

@class PTYSession;
@class PTYTab;
@class PseudoTerminal;

@interface TmuxController : NSObject {
    TmuxGateway *gateway_;
    NSMutableDictionary *windowPanes_;  // [window, pane] -> PTYSession *
    NSMutableDictionary *windows_;      // window -> [PTYTab *, refcount]
    int numOutstandingWindowResizes_;
}

@property (nonatomic, readonly) TmuxGateway *gateway;

- (id)initWithGateway:(TmuxGateway *)gateway;
- (void)openWindowsInitial;
- (void)openWindowWithId:(int)windowId;
- (PTYSession *)sessionWithAffinityForTmuxWindowId:(int)windowId;

- (void)setLayoutInTab:(PTYTab *)tab
                toLayout:(NSString *)layout;

- (PTYSession *)sessionForWindowPane:(int)windowPane;
- (PTYTab *)window:(int)window;
- (void)registerSession:(PTYSession *)aSession
               withPane:(int)windowPane
               inWindow:(int)window;
- (void)deregisterWindow:(int)window windowPane:(int)windowPane;

// This should be called after the host sends an %exit command.
- (void)detach;
- (void)windowDidResize:(PseudoTerminal *)term;
- (BOOL)hasOutstandingWindowResize;
- (void)windowPane:(int)wp
         resizedBy:(int)amount
      horizontally:(BOOL)wasHorizontal;
- (void)splitWindowPane:(int)wp vertically:(BOOL)splitVertically;
- (void)newWindowWithAffinity:(int)paneNumber;

@end
