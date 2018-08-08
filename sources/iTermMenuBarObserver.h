//
//  iTermMenuBarObserver.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/8/18.
//

#import <Cocoa/Cocoa.h>

@interface iTermMenuBarObserver : NSObject
@property (nonatomic, readonly) BOOL currentDesktopHasFullScreenWindow;
@property (nonatomic, readonly) BOOL menuBarVisible;

+ (instancetype)sharedInstance;

@end
