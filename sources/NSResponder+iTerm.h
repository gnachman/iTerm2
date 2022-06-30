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

// For inscrutable reasons scrollWheel: is not called for "changed" or "ended" momentum phases.
- (BOOL)it_wantsScrollWheelMomentumEvents;
- (void)it_scrollWheelMomentum:(NSEvent *)event;
- (BOOL)it_preferredFirstResponder;
- (BOOL)it_isTerminalResponder;

@end

@interface NSResponder (iTermFirstResponder)
- (void)toggleTriggerEnabled:(id)sender;
@end
