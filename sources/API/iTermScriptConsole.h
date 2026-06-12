//
//  iTermScriptConsole.h
//  iTerm2
//
//  Created by George Nachman on 4/19/18.
//

#import <Cocoa/Cocoa.h>

@class iTermScriptHistoryEntry;

@interface iTermScriptConsole : NSWindowController

+ (instancetype)sharedInstance;
- (void)revealTailOfHistoryEntry:(iTermScriptHistoryEntry *)entry;

@end
