//
//  TmuxController.h
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import <Cocoa/Cocoa.h>
#import "TmuxGateway.h"

@class PTYSession;

@interface TmuxController : NSObject {
    TmuxGateway *gateway_;
    NSMutableDictionary *windowPanes_;  // [window, pane] -> PTYSession *
}

@property (nonatomic, readonly) TmuxGateway *gateway;

- (id)initWithGateway:(TmuxGateway *)gateway;
- (void)openWindowsInitial;
- (PTYSession *)sessionForWindow:(int)window pane:(int)windowPane;
- (void)registerSession:(PTYSession *)aSession
               withPane:(int)windowPane
               inWindow:(int)window;
- (void)deregisterWindow:(int)window windowPane:(int)windowPane;

// This should be called after the host sends an %exit command.
- (void)detach;

@end
