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

+ (void)restoreWindowWithIdentifier:(NSString *)identifier state:(NSCoder *)state completionHandler:(void (^)(NSWindow *, NSError *))completionHandler;

+ (BOOL)willOpenWindows;

+ (void)setRestorationCompletionBlock:(void(^)())completion;

@end
