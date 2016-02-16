//
//  iTermFullScreenWindowManager.h
//  iTerm2
//
//  Created by George Nachman on 2/6/16.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermWeakReference.h"

@interface iTermFullScreenWindowManager : NSObject

- (instancetype)initWithClass:(Class)class enterFullScreenSelector:(SEL)selector;

- (void)makeWindowEnterFullScreen:(NSWindow<iTermWeaklyReferenceable> *)window;

@end
