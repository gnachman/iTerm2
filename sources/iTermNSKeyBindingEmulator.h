//
//  iTermNSKeyBindingEmulator.h
//  iTerm
//
//  Created by George Nachman on 12/8/13.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermNSKeyBindingEmulator : NSObject

// Indicates if the event should be handled by Cocoa's regular text processing path because it has
// a key binding. If this returns NO, then |extraEvents| may be filled in with additional events
// to process first. That happens when a series of keys is entered which make up a multi-key binding
// ending in an unhandleable binding.
// If this returns YES then *pointlessly will also be set. If pointlessly is set to YES then
// the caller should not pass the event to cocoa, or it will hold on to the event since it's the
// prefix of a longer series of keystrokes, none of which can possibly lead to insertText:.
- (BOOL)handlesEvent:(NSEvent *)event pointlessly:(BOOL *)pointlessly extraEvents:(NSMutableArray *)extraEvents;

@end
