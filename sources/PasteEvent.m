//
//  PasteEvent.m
//  iTerm
//
//  Created by George Nachman on 3/13/13.
//
//

#import "PasteEvent.h"

#import "NSStringITerm.h"

@implementation PasteEvent {
    NSString *_modifiedString;
}

+ (PasteEvent *)pasteEventWithString:(NSString *)string
                               flags:(iTermPasteFlags)flags
                    defaultChunkSize:(int)defaultChunkSize
                            chunkKey:(NSString *)chunkKey
                        defaultDelay:(NSTimeInterval)defaultDelay
                            delayKey:(NSString *)delayKey
                        tabTransform:(iTermTabTransformTags)tabTransform
                        spacesPerTab:(int)spacesPerTab
                               regex:(NSString *)regex
                        substitution:(NSString *)substitution {
    PasteEvent *pasteEvent = [[PasteEvent alloc] init];
    pasteEvent->_originalString = [string copy];
    pasteEvent.flags = flags;
    pasteEvent.chunkKey = chunkKey;
    pasteEvent.defaultChunkSize = defaultChunkSize;
    pasteEvent.delayKey = delayKey;
    pasteEvent.defaultDelay = defaultDelay;
    pasteEvent.tabTransform = tabTransform;
    pasteEvent.spacesPerTab = spacesPerTab;
    pasteEvent.regex = regex;
    pasteEvent.substitution = substitution;
    return pasteEvent;
}

- (NSString *)string {
    return _modifiedString ?: _originalString;
}

- (void)setModifiedString:(NSString *)modifiedString {
    _modifiedString = [modifiedString copy];
}

- (void)addPasteBracketing {
    NSString *startBracket = [NSString stringWithFormat:@"%c[200~", 27];
    NSString *endBracket = [NSString stringWithFormat:@"%c[201~", 27];
    NSArray *components = @[ startBracket, self.string, endBracket ];
    [self setModifiedString:[components componentsJoinedByString:@""]];
}

- (void)trimNewlines {
    NSCharacterSet *newlines = [NSCharacterSet newlineCharacterSet];
    [self setModifiedString:[self.string stringByTrimmingTrailingCharactersFromCharacterSet:newlines]];
}

@end
