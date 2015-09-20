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
- (BOOL)handlesEvent:(NSEvent *)event extraEvents:(NSMutableArray *)extraEvents;

@end
