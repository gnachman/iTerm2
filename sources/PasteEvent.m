//
//  PasteEvent.m
//  iTerm
//
//  Created by George Nachman on 3/13/13.
//
//

#import "PasteEvent.h"

@implementation PasteEvent

+ (PasteEvent *)pasteEventWithString:(NSString *)string flags:(int)flags {
    PasteEvent *pasteEvent = [[[PasteEvent alloc] init] autorelease];
    pasteEvent->string_ = [string copy];
    pasteEvent->flags_ = flags;
    return pasteEvent;
}

- (void)dealloc {
    [string_ release];
    [super dealloc];
}

- (NSString *)string {
    return string_;
}

- (int)flags {
    return flags_;
}

@end
