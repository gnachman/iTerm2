//
//  PseudoTerminalRestorer.h
//  iTerm
//
//  Created by George Nachman on 10/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PseudoTerminalRestorer : NSObject {

}

#ifndef BLOCKS_NOT_AVAILABLE
+ (void)restoreWindowWithIdentifier:(NSString *)identifier state:(NSCoder *)state completionHandler:(void (^)(NSWindow *, NSError *))completionHandler;
#endif  // BLOCKS_NOT_AVAILABLE

+ (BOOL)willOpenWindows;
@end
