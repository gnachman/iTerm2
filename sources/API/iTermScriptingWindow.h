//
//  iTermScriptingWindow.h
//  iTerm2
//
//  Created by George Nachman on 7/6/16.
//
//

#import <Foundation/Foundation.h>
#import "PTYWindow.h"

// This wraps iTermWindow and iTermPanel so that AppleScript thinks they have
// the same class. That makes AppleScript, which is a dumpster fire, happy.
// This uses a combination of brute force and objc runtime cleverness.
@interface iTermScriptingWindow : NSObject

@property(nonatomic, readonly) NSWindow *underlyingWindow;

+ (instancetype)scriptingWindowWithWindow:(NSWindow *)window;

@end
