//
//  NSResponder+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/10/18.
//

#import <Cocoa/Cocoa.h>

@interface NSResponder (iTerm)

// For inscrutable reasons scrollWheel: is not called for "changed" or "ended" momentum phases.
- (BOOL)it_wantsScrollWheelMomentumEvents;
- (void)it_scrollWheelMomentum:(NSEvent *)event;
- (BOOL)it_preferredFirstResponder;
- (BOOL)it_isTerminalResponder;
// FFM won't cause focus to be taken to controlling terminal except on mouse exit.
- (BOOL)it_focusFollowsMouseImmune;
@end

@interface NSResponder (iTermFirstResponder)
- (void)toggleTriggerEnabled:(id)sender;
@end
