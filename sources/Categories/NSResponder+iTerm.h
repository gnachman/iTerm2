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
// Override to return YES while this responder should keep keyboard focus even when FFM would
// otherwise move it to another pane or window.
- (BOOL)it_focusFollowsMouseHoldsFocus;
// YES if the receiver or one of its superviews holds focus against FFM.
- (BOOL)it_focusFollowsMouseHoldsFocusInHierarchy;
@end

@interface NSResponder (iTermFirstResponder)
- (void)toggleTriggerEnabled:(id)sender;
@end
