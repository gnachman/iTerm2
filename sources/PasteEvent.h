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

typedef NS_OPTIONS(NSUInteger, iTermPasteFlags) {
    // These values have the same values as flags in PTYSessionPasteFlags
    kPasteFlagsEscapeSpecialCharacters = (1 << 0),
    kPasteFlagsWithShellEscapedTabs = (1 << 2),

    // These are unique to sanitization
    kPasteFlagsSanitizingNewlines = (1 << 3),
    kPasteFlagsRemovingUnsafeControlCodes = (1 << 4),
    kPasteFlagsBracket = (1 << 5)
};

@interface PasteEvent : NSEvent {
    NSString *string_;
    int flags_;
}

+ (PasteEvent *)pasteEventWithString:(NSString *)string flags:(int)flags;
- (NSString *)string;
- (int)flags;

@end
