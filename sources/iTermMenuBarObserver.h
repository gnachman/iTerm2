//
//  iTermMenuBarObserver.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/8/18.
//

#import <Cocoa/Cocoa.h>

@interface iTermMenuBarObserver : NSObject

- (BOOL)menuBarVisibleOnScreen:(NSScreen *)screen;

+ (instancetype)sharedInstance;

@end
