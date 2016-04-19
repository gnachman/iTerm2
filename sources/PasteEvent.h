//
//  PasteEvent.h
//  iTerm
//
//  Created by George Nachman on 3/13/13.
//
//

#import <Cocoa/Cocoa.h>

// These values correspond to cell tags on the matrix.
typedef NS_ENUM(NSInteger, iTermTabTransformTags) {
    kTabTransformNone = 0,
    kTabTransformConvertToSpaces = 1,
    kTabTransformEscapeWithCtrlV = 2
};

// These flags are used on the tags in menu items.
typedef NS_OPTIONS(unsigned int, PTYSessionPasteFlags) {
    kPTYSessionPasteEscapingSpecialCharacters = (1 << 0),
    kPTYSessionPasteSlowly = (1 << 1),
    kPTYSessionPasteWithShellEscapedTabs = (1 << 2)
};

typedef NS_OPTIONS(NSUInteger, iTermPasteFlags) {
    // These values have the same values as flags in PTYSessionPasteFlags
    kPasteFlagsEscapeSpecialCharacters = (1 << 0),
    // 1 and 2 aren't used.

    // These are unique to sanitization
    kPasteFlagsSanitizingNewlines = (1 << 3),
    kPasteFlagsRemovingUnsafeControlCodes = (1 << 4),
    kPasteFlagsBracket = (1 << 5),
    kPasteFlagsConvertUnicodePunctuation = (1 << 7),

    // Only used by key actions and paste special
    kPasteFlagsBase64Encode = (1 << 6),

    // Wait for prompt before each line
    kPasteFlagsCommands = (1 << 8),

    // New additions
    kPasteFlagsRemovingNewlines = (1 << 9),

    kPasteFlagsUseRegexSubstitution = (1 << 10),
};

@interface PasteEvent : NSEvent

@property(nonatomic, copy) NSString *string;
@property(nonatomic, assign) iTermPasteFlags flags;
@property(nonatomic, assign) int defaultChunkSize;
@property(nonatomic, copy) NSString *chunkKey;
@property(nonatomic, assign) NSTimeInterval defaultDelay;
@property(nonatomic, copy) NSString *delayKey;
@property(nonatomic, assign) iTermTabTransformTags tabTransform;
@property(nonatomic, assign) int spacesPerTab;
@property(nonatomic, copy) NSString *regex;
@property(nonatomic, copy) NSString *substitution;

+ (instancetype)pasteEventWithString:(NSString *)string
                               flags:(iTermPasteFlags)flags
                    defaultChunkSize:(int)defaultChunkSize
                            chunkKey:(NSString *)chunkKey
                        defaultDelay:(NSTimeInterval)defaultDelay
                            delayKey:(NSString *)delayKey
                        tabTransform:(iTermTabTransformTags)tabTransform
                        spacesPerTab:(int)spacePerTab
                               regex:(NSString *)regex
                        substitution:(NSString *)substitution;

@end
