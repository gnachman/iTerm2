//
//  iTermFullScreenWindowManager.h
//  iTerm2
//
//  Created by George Nachman on 2/6/16.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermFullScreenWindowManager : NSObject

- (instancetype)initWithClass:(Class)class enterFullScreenSelector:(SEL)selector;

- (void)makeWindowEnterFullScreen:(NSWindow *)window;

@end
