//
//  iTermMenuBarObserver.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/8/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermMenuBarObserver : NSObject

- (BOOL)menuBarVisibleOnScreen:(NSScreen * _Nullable)screen;

+ (instancetype)sharedInstance;

@end

NS_ASSUME_NONNULL_END
