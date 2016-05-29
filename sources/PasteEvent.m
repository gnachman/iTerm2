//
//  PasteEvent.m
//  iTerm
//
//  Created by George Nachman on 3/13/13.
//
//

#import "PasteEvent.h"

@implementation PasteEvent

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
    PasteEvent *pasteEvent = [[[PasteEvent alloc] init] autorelease];
    pasteEvent.string = string;
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

- (void)dealloc {
    [_string release];
    [_chunkKey release];
    [_delayKey release];
    [_regex release];
    [_substitution release];
    [super dealloc];
}

@end
