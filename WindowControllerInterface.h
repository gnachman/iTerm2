//
//  WindowControllerInterface.h
//  iTerm
//
//  Created by George Nachman on 10/19/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
@class PTYSession;
@class PTYTabView;

@protocol WindowControllerInterface <NSObject>

- (void)sessionInitiatedResize:(PTYSession*)session width:(int)width height:(int)height;
- (BOOL)fullScreen;
- (BOOL)sendInputToAllSessions;
- (void)closeSession:(PTYSession*)aSession;
- (IBAction)nextSession:(id)sender;
- (IBAction)previousSession:(id)sender;
- (void)setLabelColor:(NSColor *)color forTabViewItem:tabViewItem;
- (void)enableBlur;
- (void)disableBlur;
- (BOOL)tempTitle;
- (void)fitWindowToSession:(PTYSession*)session;
- (PTYTabView *)tabView;
- (PTYSession *)currentSession;
- (void)sendInputToAllSessions:(NSData *)data;
- (void)setWindowTitle;
- (void)resetTempTitle;

- (void)windowSetFrameTopLeftPoint:(NSPoint)point;
- (void)windowPerformMiniaturize:(id)sender;
- (void)windowDeminiaturize:(id)sender;
- (void)windowOrderFront:(id)sender;
- (void)windowOrderBack:(id)sender;
- (BOOL)windowIsMiniaturized;
- (NSRect)windowFrame;
- (NSScreen*)windowScreen;

@end
