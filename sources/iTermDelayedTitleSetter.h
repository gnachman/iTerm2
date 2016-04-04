//
//  iTermDelayedTitleSetter.h
//  iTerm2
//
//  Created by George Nachman on 11/15/15.
//
//

#import <Cocoa/Cocoa.h>

extern NSString *const kDelayedTitleSetterSetTitle;
// User info key for new title
extern NSString *const kDelayedTitleSetterTitleKey;

// In bug 2593, we see a crazy thing where setting the window title right
// after a window is created causes it to have the wrong background color.
// A delay of 0 doesn't fix it. I'm at wit's end here, so this will have to
// do until a better explanation comes along.
// In bug 3957, we see that GNU screen is buggy and sends a crazy number of title changes.
// We want to coalesce them to avoid the title flickering like mad. Also, setting the title
// seems to be relatively slow, so we don't want to spend too much time doing that if the
// terminal goes nuts and sends lots of title-change sequences.

// This object exists to avoid keeping a PTYWindow or PseudoTerminal from getting dealloc'ed
// while a delayed title-set is happening. The window property is a weak reference and this object
// can exist for about a tenth of a second after a window is dealloc'ed.
@interface iTermDelayedTitleSetter : NSObject

@property(nonatomic, assign) NSWindow *window;

- (void)setTitle:(NSString *)title;

@end
