//
//  VT100XtermParser.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "VT100XtermParser.h"
#import "NSData+iTerm.h"

static NSString *const kXtermParserSavedStateDataKey = @"kXtermParserSavedStateDataKey";
static NSString *const kXtermParserSavedStateBytesUsedKey = @"kXtermParserSavedStateBytesUsedKey";
static NSString *const kXtermParserSavedStateModeKey = @"kXtermParserSavedStateModeKey";
static NSString *const kXtermParserSavedStateStateKey = @"kXtermParserSavedStateStateKey";

// Nonstandard Linux OSC P nrrggbb ST to change color palette
// entry. Since no mode number exists for this code, we use -1 as a temporary placeholder until
// it can be translated into XTERMCC_SET_PALETTE.
static const int kLinuxSetPaletteMode = -1;

// This parser operates as a state machine. Each state has a corresponding
// method that implements a hand-build parser.
typedef enum {
    // Reading the mode at the start. Either a number followed by a semicolon, or the letter P.
    kXtermParserParsingModeState,

    // Reading the 7 digits after mode letter P.
    kXtermParserParsingPState,

    // Reading the string after the mode number and semicolon, up to and including the terminator.
    kXtermParserParsingStringState,

    // Have encountered an illegal character (e.g., bogus mode). Continue until the code ends as a
    // normal OSC would.
    kXtermParserFailingState,

    // These states will cause the state machine to terminate.

    // Return VT100_NOTSUPPORT.
    kXtermParserFailedState,

    // Return a legal token (assuming the mode is supported).
    kXtermParserFinishedState,

    // Save state into the savedState dictionary, backtrack all consumed data, and have client try
    // again when more data is available.
    kXtermParserOutOfDataState,
} iTermXtermParserState;

@implementation VT100XtermParser

// Read either an integer followed by a semicolon or letter "P".
+ (iTermXtermParserState)parseModeFromContext:(iTermParserContext *)context mode:(int *)mode {
    if (iTermParserConsumeInteger(context, mode)) {
        // Read an integer. Either out of data or a semicolon should follow; anything else is
        // a malformed input.
        if (iTermParserCanAdvance(context)) {
            if (iTermParserPeek(context) == ';') {
                // Semicolon
                iTermParserAdvance(context);
                return kXtermParserParsingStringState;
            } else {
                // Malformed
                return kXtermParserFailingState;
            }
        } else {
            // Out of data.
            return kXtermParserOutOfDataState;
        }
    } else {
        // Failed to read an integer. Could be out of data, could be the nonstandard 'P' code, or
        // could be a malformed input.
        if (iTermParserCanAdvance(context)) {
            if (iTermParserPeek(context) == 'P') {
                // Got a nonstandard P code.
                iTermParserAdvance(context);
                *mode = kLinuxSetPaletteMode;
                return kXtermParserParsingPState;
            } else {
                // Malformed input.
                return kXtermParserFailingState;
            }
        } else {
            // Out of data.
            return kXtermParserOutOfDataState;
        }
    }
}

// Read seven characters and append them to 'data'.
+ (iTermXtermParserState)parsePFromContext:(iTermParserContext *)context data:(NSMutableData *)data {
    for (int i = 0; i < 7; i++) {
        unsigned char c;
        if (!iTermParserTryConsume(context, &c)) {
            return kXtermParserOutOfDataState;
        }
        [data appendBytes:&c length:1];
    }
    return kXtermParserFinishedState;
}

// Read the next characters and append them to data. Various substrings may end parsing:
//   ESC ]                This is ignored
//   ESC \ or BEL         Finishes parsing
//   ESC <anything else>  Fails
//   File= KVP code       Finish prior to true end of OSC
//   CAN or SUB           Fails
// Other characters are appended to |data|.
+ (iTermXtermParserState)parseNextCharsInStringFromContext:(iTermParserContext *)context
                                                      data:(NSMutableData *)data
                                                      mode:(int)mode {
    iTermXtermParserState nextState = kXtermParserParsingStringState;
    do {
        if (!iTermParserCanAdvance(context)) {
            nextState = kXtermParserOutOfDataState;
        } else {
            unsigned char c = iTermParserConsume(context);
            BOOL append = YES;
            switch (c) {
                case VT100CC_ESC:
                    if (iTermParserTryConsume(context, &c)) {
                        if (c == ']') {
                            append = NO;
                            nextState = kXtermParserParsingStringState;
                        } else if (c == '\\') {
                            nextState = kXtermParserFinishedState;
                        } else {
                            nextState = kXtermParserFailedState;
                        }
                    } else {
                        // Ended after ESC. Backtrack over the ESC so it can be parsed again when more
                        // data arrives.
                        iTermParserBacktrackBy(context, 1);
                        nextState = kXtermParserOutOfDataState;
                    }
                    break;

                case ':':
                    if ((mode == 50 || mode == 1337) &&
                        [data hasPrefixOfBytes:"File=" length:5]) {
                        // This is a wonky special case for file downloads. The OSC code can be
                        // really, really big. So we mark it as ended at the colon, and the client
                        // is responsible for handling this properly. TODO: Clean this up.
                        nextState = kXtermParserFinishedState;
                    } else {
                        nextState = kXtermParserParsingStringState;
                    }
                    break;

                case VT100CC_CAN:
                case VT100CC_SUB:
                    nextState = kXtermParserFailedState;
                    break;

                case VT100CC_BEL:
                    nextState = kXtermParserFinishedState;
                    break;

                default:
                    nextState = kXtermParserParsingStringState;
                    break;
            }
            if (append && nextState == kXtermParserParsingStringState) {
                [data appendBytes:&c length:1];
            }
        }
    } while (nextState == kXtermParserParsingStringState);
    return nextState;
}

// Returns the enum value for the mode.
+ (VT100TerminalTokenType)tokenTypeForMode:(int)mode {
    static NSDictionary *theMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        theMap =
            @{ @(kLinuxSetPaletteMode): @(XTERMCC_SET_PALETTE),
               @0: @(XTERMCC_WINICON_TITLE),
               @1: @(XTERMCC_ICON_TITLE),
               @2: @(XTERMCC_WIN_TITLE),
               @4: @(XTERMCC_SET_RGB),
               @6: @(XTERMCC_PROPRIETARY_ETERM_EXT),
               @9: @(ITERM_GROWL),
               // 50 is a nonstandard escape code implemented by Konsole.
               // xterm since started using it for setting the font, so 1337 is the preferred code
               // for this in iTerm2.
               @50: @(XTERMCC_SET_KVP),
               @52: @(XTERMCC_PASTE64),
               @133: @(XTERMCC_FINAL_TERM),
               @1337: @(XTERMCC_SET_KVP),
           };
        [theMap retain];
    });


    NSNumber *enumNumber = theMap[@(mode)];
    if (enumNumber) {
        return [enumNumber intValue];
    } else {
        return VT100_NOTSUPPORT;
    }
}

+ (void)decodeFromContext:(iTermParserContext *)context
                    token:(VT100Token *)result
                 encoding:(NSStringEncoding)encoding
               savedState:(NSMutableDictionary *)savedState {
    // Initialize the state.
    NSMutableData *data = [NSMutableData data];
    int mode = 0;
    iTermXtermParserState state = kXtermParserParsingModeState;

    if (savedState.count) {
        data = savedState[kXtermParserSavedStateDataKey];
        iTermParserAdvanceMultiple(context,
                                   [savedState[kXtermParserSavedStateBytesUsedKey] intValue]);
        mode = [savedState[kXtermParserSavedStateModeKey] intValue];
        state = [savedState[kXtermParserSavedStateStateKey] intValue];
    } else {
        iTermParserConsumeOrDie(context, VT100CC_ESC);
        iTermParserConsumeOrDie(context, ']');
    }

    iTermXtermParserState previousState = state;

    // Run the state machine.
    while (1) {
        iTermXtermParserState stateSwitchedOn = state;
        switch (state) {
            case kXtermParserParsingModeState:
                state = [self parseModeFromContext:context mode:&mode];
                break;

            case kXtermParserParsingPState:
                state = [self parsePFromContext:context data:data];
                break;

            case kXtermParserParsingStringState:
                state = [self parseNextCharsInStringFromContext:context data:data mode:mode];
                break;

            case kXtermParserFailingState:
                state = [self parseNextCharsInStringFromContext:context data:nil mode:0];

                // Convert success states into failure states.
                if (state == kXtermParserFinishedState) {
                    state = kXtermParserFailedState;
                } else if (state == kXtermParserParsingStringState) {
                    // This should never happen but is here for the sake of completeness.
                    state = kXtermParserFailingState;
                }
                break;

            case kXtermParserFailedState:
                [savedState removeAllObjects];
                result->type = VT100_NOTSUPPORT;
                return;

            case kXtermParserFinishedState:
                result.string = [[[NSString alloc] initWithData:data
                                                       encoding:encoding] autorelease];
                result->type = [self tokenTypeForMode:mode];
                if (result->type == XTERMCC_SET_KVP) {
                    [self parseKeyValuePairInToken:result];
                }
                return;
                
            case kXtermParserOutOfDataState:
                savedState[kXtermParserSavedStateDataKey] = data;
                savedState[kXtermParserSavedStateBytesUsedKey] = @(iTermParserNumberOfBytesConsumed(context));
                savedState[kXtermParserSavedStateModeKey] = @(mode);
                savedState[kXtermParserSavedStateStateKey] = @(previousState);

                iTermParserBacktrack(context);
                result->type = VT100_WAIT;
                return;
        }
        previousState = stateSwitchedOn;
    }
}

+ (void)parseKeyValuePairInToken:(VT100Token *)token {
    // argument is of the form key=value
    // key: Sequence of characters not = or ^G
    // value: Sequence of characters not ^G
    NSString* argument = token.string;
    NSRange eqRange = [argument rangeOfString:@"="];
    NSString* key;
    NSString* value;
    if (eqRange.location != NSNotFound) {
        key = [argument substringToIndex:eqRange.location];;
        value = [argument substringFromIndex:eqRange.location+1];
    } else {
        key = argument;
        value = @"";
    }
    
    token.kvpKey = key;
    token.kvpValue = value;
}

@end
