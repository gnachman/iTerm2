//
//  NSResponder+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/10/18.
//

#import <Cocoa/Cocoa.h>

@interface NSResponder (iTerm)

@property (nonatomic, readonly) BOOL it_shouldIgnoreFirstResponderChanges;

- (void)it_ignoreFirstResponderChangesInBlock:(void (^)(void))block;

@end
