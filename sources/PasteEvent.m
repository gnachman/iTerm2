//
//  PasteEvent.m
//  iTerm
//
//  Created by George Nachman on 3/13/13.
//
//

#import "PasteEvent.h"

#import "NSArray+iTerm.h"
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
                        substitution:(NSString *)substitution
  shouldPasteNewlinesOutsideBrackets:(BOOL)shouldPasteNewlinesOutsideBrackets {
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
    pasteEvent.shouldPasteNewlinesOutsideBrackets = shouldPasteNewlinesOutsideBrackets;
    return pasteEvent;
}

- (NSString *)string {
    return _modifiedString ?: _originalString;
}

- (void)setModifiedString:(NSString *)modifiedString {
    _modifiedString = [modifiedString copy];
}

- (void)addPasteBracketing {
    if (self.shouldPasteNewlinesOutsideBrackets) {
        NSArray<iTermTuple<NSString *, NSString *> *> *tuples = [self.string it_componentsSeparatedByAnyStringIn:@[@"\r", @"\n", @"\r\n"]];
        tuples = [tuples mapWithBlock:^id _Nullable(iTermTuple<NSString *, NSString *> *tuple) {
            return [tuple mapFirst:^id _Nonnull(NSString *line) {
                return [line it_pasteBracketed];
            }];
        }];
        NSArray<NSString *> *linesWithNewlines = [tuples mapWithBlock:^id _Nullable(iTermTuple<NSString *,NSString *> *tuple) {
            return [tuple.firstObject stringByAppendingString:tuple.secondObject ?: @""];
        }];
        NSString *joined = [linesWithNewlines componentsJoinedByString:@""];
        [self setModifiedString:joined];
    } else {
        [self setModifiedString:[self.string it_pasteBracketed]];
    }
}

- (void)trimNewlines {
    NSCharacterSet *newlines = [NSCharacterSet newlineCharacterSet];
    [self setModifiedString:[self.string stringByTrimmingTrailingCharactersFromCharacterSet:newlines]];
}

@end
