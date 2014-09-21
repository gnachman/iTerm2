//
//  PasteEvent.h
//  iTerm
//
//  Created by George Nachman on 3/13/13.
//
//

#import <Cocoa/Cocoa.h>

typedef NS_OPTIONS(int, PTYSessionPasteFlags) {
    kPTYSessionPasteEscapingSpecialCharacters = (1 << 0),
    kPTYSessionPasteSlowly = (1 << 1),
    kPTYSessionPasteWithShellEscapedTabs = (1 << 2)
};

@interface PasteEvent : NSEvent {
    NSString *string_;
    int flags_;
}

+ (PasteEvent *)pasteEventWithString:(NSString *)string flags:(int)flags;
- (NSString *)string;
- (int)flags;

@end
