//
//  FakeWindow.h
//  iTerm
//
//  Created by George Nachman on 10/18/10.
//  Copyright 2010 George Nachman. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PseudoTerminal.h"
#import "WindowControllerInterface.h"

@interface FakeWindow : NSObject <WindowControllerInterface>


- (instancetype)initFromRealWindow:(NSWindowController<iTermWindowController> *)aTerm
                           session:(PTYSession*)aSession;

// PseudoTerminal should call this after adding the session to its tab view.
- (void)rejoin:(NSWindowController<iTermWindowController> *)aTerm;

@end
