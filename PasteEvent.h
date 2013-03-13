//
//  PasteEvent.h
//  iTerm
//
//  Created by George Nachman on 3/13/13.
//
//

#import <Cocoa/Cocoa.h>

@interface PasteEvent : NSEvent {
    NSString *string_;
    int flags_;
}

+ (PasteEvent *)pasteEventWithString:(NSString *)string flags:(int)flags;
- (NSString *)string;
- (int)flags;

@end
