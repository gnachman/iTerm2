//
//  iTermNSKeyBindingEmulator.h
//  iTerm
//
//  Created by George Nachman on 12/8/13.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermNSKeyBindingEmulator : NSObject

// Returns YES if the user's key bindings should handle this event.
- (BOOL)handlesEvent:(NSEvent *)event;

@end
