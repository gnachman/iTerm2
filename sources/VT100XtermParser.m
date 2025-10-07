//
//  VT100XtermParser.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "VT100XtermParser.h"
#import "DebugLogging.h"
#import "NSData+iTerm.h"

static NSString *const kXtermParserSavedStateDataKey = @"kXtermParserSavedStateDataKey";
static NSString *const kXtermParserSavedStateBytesUsedKey = @"kXtermParserSavedStateBytesUsedKey";
static NSString *const kXtermParserSavedStateModeKey = @"kXtermParserSavedStateModeKey";
static NSString *const kXtermParserSavedStateStateKey = @"kXtermParserSavedStateStateKey";
static NSString *const kXtermParserMultitokenHeaderEmittedkey = @"kXtermParserMultitokenHeaderEmittedkey";

// Nonstandard Linux OSC P nrrggbb ST to change color palette
// entry. Since no mode number exists for this code, we use -1 as a temporary placeholder until
// it can be translated into XTERMCC_SET_PALETTE.
static const int kLinuxSetPaletteMode = -1;

// If this is APC ... ST instead of OSC ... ST, use this for the mode since APC doesn't have modes.
static const int kAPCMode = -2;

// This parser operates as a state machine. Each state has a corresponding
// method that implements a hand-build parser.
typedef enum {
    // Reading the mode at the start. Either a number followed by a semicolon, or the letter P.
    kXtermParserParsingModeState,

    // Accept only ST (ESC+backslash or BEL). Happens when there is a mode but no parameter.
    kTermParserParsingStateST,

    // Reading the 7 digits after mode letter P.
    kXtermParserParsingPState,

    // Reading the string after the mode number and semicolon, up to and including the terminator.
    kXtermParserParsingStringState,

    // Have encountered an illegal character (e.g., bogus mode). Continue until the code ends as a
    // normal OSC would.
    kXtermParserFailingState,

    // Finished parsing the header portion of a multitoken code.
    kXtermParserHeaderEndState,

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
    BOOL overflow = NO;
    iTermParserContext saved = *context;
    if (iTermParserConsumeInteger(context, mode, &overflow)) {
        if (overflow) {
            return kXtermParserFailingState;
        }
        // Read an integer. Either out of data or a semicolon should follow; anything else is
        // a malformed input.
        if (iTermParserCanAdvance(context)) {
            if (iTermParserPeek(context) == ';') {
                // Semicolon
                iTermParserAdvance(context);
                return kXtermParserParsingStringState;
            } else {
                // Could be an ST exactly after the mode (e.g., for OSC 110 through 119).
                return kTermParserParsingStateST;
            }
        } else {
            // Out of data. Backtrack to the start of the int because when this is resumed later
            // with more data, we must begin parsing the mode all over again.
            *context = saved;
            return kXtermParserOutOfDataState;
        }
    } else {
        // Failed to read an integer. Could be out of data, could be the nonstandard 'P' code, or
        // could be a malformed input.
        if (iTermParserCanAdvance(context)) {
            unsigned char c = iTermParserPeek(context);
            if (c == 'P') {
                // Got a nonstandard P code.
                iTermParserAdvance(context);
                *mode = kLinuxSetPaletteMode;
                return kXtermParserParsingPState;
            } else if (c == ';') {
                // This isn't documented AFAICT but if you leave out the mode then it defaults to 0.
                // This is how xterm works and some users expect it (see bug 3371).
                iTermParserAdvance(context);
                *mode = 0;
                return kXtermParserParsingStringState;
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

+ (iTermXtermParserState)parseSTFromContext:(iTermParserContext *)context {
    const unsigned char c = iTermParserConsume(context);
    if (c == VT100CC_BEL) {
        return kXtermParserFinishedState;
    }
    if (c != VT100CC_ESC) {
        return kXtermParserFailedState;
    }
    unsigned char c2 = 0;
    if (!iTermParserTryConsume(context, &c2)) {
        iTermParserBacktrackBy(context, 1);
        return kXtermParserOutOfDataState;
    }
    if (c2 != '\\') {
        return kXtermParserFailingState;
    }
    return kXtermParserFinishedState;
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
//
// When 8-bit control sequences are supported, the following behaviors are added:
//   C1 ST                Finished parsing
//   C1 OSC               This is ignored
//   Other C1 codes       Fails
// Other characters are appended to |data|.
+ (iTermXtermParserState)parseNextCharsInStringFromContext:(iTermParserContext *)context
                              support8BitControlCharacters:(BOOL)support8BitControlCharacters
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
                        ([data hasPrefixOfBytes:"File=" length:5] ||
                         [data hasPrefixOfBytes:"Copy=" length:5])) {
                        // This is a wonky special case for file downloads. The OSC code can be
                        // really, really big. So we mark it as ended at the colon, and the client
                        // is responsible for handling this properly.
                        nextState = kXtermParserHeaderEndState;
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

                case VT100CC_C1_ST:
                    if (support8BitControlCharacters) {
                        nextState = kXtermParserFinishedState;
                        break;
                    }
                    // fall through
                case VT100CC_C1_OSC:
                    if (support8BitControlCharacters) {
                        append = NO;
                        nextState = kXtermParserParsingStringState;
                        break;
                    }
                    // fall through
                case VT100CC_C1_IND:
                case VT100CC_C1_NEL:
                case VT100CC_C1_HTS:
                case VT100CC_C1_RI:
                case VT100CC_C1_SS2:
                case VT100CC_C1_SS3:
                case VT100CC_C1_DCS:
                case VT100CC_C1_SPA:
                case VT100CC_C1_EPA:
                case VT100CC_C1_SOS:
                case VT100CC_C1_DECID:
                case VT100CC_C1_CSI:
                case VT100CC_C1_PM:
                case VT100CC_C1_APC:
                    if (support8BitControlCharacters) {
                        nextState = kXtermParserFailedState;
                        break;
                    }
                    // fall through

                default:
                    nextState = kXtermParserParsingStringState;
                    break;
            }
            if (append && nextState == kXtermParserParsingStringState) {
                [data appendBytes:&c length:1];
                const NSUInteger maxLength = 1048576;
                if (data.length >= maxLength) {
                    DLog(@"Truncate very long OSC");
                    nextState = kXtermParserFinishedState;
                }
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
            @{
               @(kAPCMode): @(VT100_APC),
               @(kLinuxSetPaletteMode): @(XTERMCC_SET_PALETTE),
               @0: @(XTERMCC_WINICON_TITLE),
               @1: @(XTERMCC_ICON_TITLE),
               @2: @(XTERMCC_WIN_TITLE),
               @4: @(XTERMCC_SET_RGB),
               @6: @(XTERMCC_PROPRIETARY_ETERM_EXT),
               @7: @(XTERMCC_PWD_URL),
               @8: @(XTERMCC_LINK),
               @9: @(ITERM_USER_NOTIFICATION),

               // See -[VT100Terminal xtermIndexForTerminalColorIndex:], which has the inverse map.
               @10: @(XTERMCC_TEXT_FOREGROUND_COLOR),
               @11: @(XTERMCC_TEXT_BACKGROUND_COLOR),
               @12: @(XTERMCC_SET_TEXT_CURSOR_COLOR),
               @17: @(XTERMCC_SET_HIGHLIGHT_COLOR),
               @19: @(XTERMCC_SET_HIGHLIGHT_FOREGROUND_COLOR),
               @22: @(XTERMCC_SET_POINTER_SHAPE),

               // 50 is a nonstandard escape code implemented by Konsole.
               // xterm since started using it for setting the font, so 1337 is the preferred code
               // for this in iTerm2.
               @50: @(XTERMCC_SET_KVP),
               @52: @(XTERMCC_PASTE64),
               @104: @(XTERMCC_RESET_COLOR),
               
               @(110): @(XTERMCC_RESET_VT100_TEXT_FOREGROUND_COLOR),
               @(111): @(XTERMCC_RESET_VT100_TEXT_BACKGROUND_COLOR),
               @(112): @(XTERMCC_RESET_TEXT_CURSOR_COLOR),
               @(117): @(XTERMCC_RESET_HIGHLIGHT_COLOR),
               @(119): @(XTERMCC_RESET_HIGHLIGHT_FOREGROUND_COLOR),
               @133: @(XTERMCC_FINAL_TERM),
               @134: @(XTERMCC_FRAMER_WRAPPER),
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

+ (void)emitIncidentalForSetKvpHeaderInVector:(CVector *)vector
                                         data:(NSData *)data
                                     encoding:(NSStringEncoding)encoding {
    VT100Token *headerToken = [VT100Token token];
    headerToken->type = XTERMCC_MULTITOKEN_HEADER_SET_KVP;
    headerToken.string = [[[NSString alloc] initWithData:data
                                                encoding:encoding] autorelease];
    [self parseKeyValuePairInToken:headerToken];
    [headerToken retain];
    // The analyzer thinks this leaks but it does not.
    CVectorAppend(vector, headerToken);
}

+ (void)emitIncidentalForMultitokenBodyInVector:(CVector *)vector
                                           data:(NSData *)data
                                       encoding:(NSStringEncoding)encoding {
    VT100Token *token = [VT100Token token];
    token->type = XTERMCC_MULTITOKEN_BODY;
    token.string = [[[NSString alloc] initWithData:data
                                          encoding:encoding] autorelease];
    [token retain];
    // The analyzer thinks this leaks but it does not.
    CVectorAppend(vector, token);
}

+ (void)decodeFromContext:(iTermParserContext *)context
              incidentals:(CVector *)incidentals
                    token:(VT100Token *)result
                 encoding:(NSStringEncoding)encoding
               savedState:(NSMutableDictionary *)savedState {
    // Initialize the state.
    NSMutableData *data = [NSMutableData data];
    int mode = 0;
    iTermXtermParserState state = kXtermParserParsingModeState;
    BOOL multitokenHeaderEmitted = NO;
    BOOL support8BitControlCharacters = (encoding == NSASCIIStringEncoding || encoding == NSISOLatin1StringEncoding);

    if (savedState.count) {
        data = savedState[kXtermParserSavedStateDataKey];
        iTermParserAdvanceMultiple(context,
                                   [savedState[kXtermParserSavedStateBytesUsedKey] intValue]);
        mode = [savedState[kXtermParserSavedStateModeKey] intValue];
        state = [savedState[kXtermParserSavedStateStateKey] intValue];
        multitokenHeaderEmitted = [savedState[kXtermParserMultitokenHeaderEmittedkey] boolValue];
    } else {
        DLog(@"Starting fresh parse (no saved state), datalen=%d", iTermParserLength(context));
        unsigned char peek = iTermParserPeek(context);
        BOOL apc = NO;
        if (support8BitControlCharacters && (peek == VT100CC_C1_OSC ||
                                             peek == VT100CC_C1_APC)) {
            if (peek == VT100CC_C1_APC) {
                apc = YES;
            }
            iTermParserConsume(context);
        } else {
            iTermParserConsumeOrDie(context, VT100CC_ESC);
            // 99% of the time the next byte is a ], but it could be a _ which is APC (used by tmux).
            if (iTermParserConsume(context) == '_') {
                apc = YES;
            }
        }
        if (apc) {
            mode = kAPCMode;
            state = kXtermParserParsingStringState;
        }
    }

    iTermXtermParserState previousState = state;

    if (iTermParserLength(context) + iTermParserNumberOfBytesConsumed(context) > 0x7f000000) {
        state = kXtermParserFailedState;
    }
    // Run the state machine.
    while (1) {
        iTermXtermParserState stateSwitchedOn = state;
        switch (state) {
            case kXtermParserParsingModeState:
                state = [self parseModeFromContext:context mode:&mode];
                break;

            case kTermParserParsingStateST:
                state = [self parseSTFromContext:context];
                break;

            case kXtermParserParsingPState:
                state = [self parsePFromContext:context data:data];
                break;

            case kXtermParserParsingStringState:
                state = [self parseNextCharsInStringFromContext:context
                                   support8BitControlCharacters:support8BitControlCharacters
                                                           data:data mode:mode];
                break;

            case kXtermParserHeaderEndState:
                // There's currently only one multitoken mode. Emit a header for it as an incidental.
                assert([self tokenTypeForMode:mode] == XTERMCC_SET_KVP);
                DLog(@"Emitting header incidental with data=%@", data);
                [self emitIncidentalForSetKvpHeaderInVector:incidentals
                                                       data:data
                                                   encoding:encoding];
                DLog(@"Header emitted, transitioning to MULTITOKEN_BODY mode");
                state = kXtermParserParsingStringState;
                mode = XTERMCC_MULTITOKEN_BODY;
                multitokenHeaderEmitted = YES;
                [data setLength:0];
                break;

            case kXtermParserFailingState:
                state = [self parseNextCharsInStringFromContext:context
                                   support8BitControlCharacters:support8BitControlCharacters
                                                           data:nil
                                                           mode:0];

                // Convert success states into failure states.
                if (state == kXtermParserFinishedState) {
                    state = kXtermParserFailedState;
                } else if (state == kXtermParserParsingStringState ||  // Shouldn't happen
                           state == kXtermParserHeaderEndState) {
                    state = kXtermParserFailingState;
                }
                break;

            case kXtermParserFailedState:
                [savedState removeAllObjects];
                result->type = VT100_NOTSUPPORT;
                return;

            case kXtermParserFinishedState:
                if (multitokenHeaderEmitted) {
                    if (data.length) {
                        DLog(@"Emitting final body incidental with data=%@", data);
                        [self emitIncidentalForMultitokenBodyInVector:incidentals
                                                                 data:data
                                                             encoding:encoding];
                        [data setLength:0];
                    }
                    DLog(@"Multitoken complete, returning MULTITOKEN_END");
                    result->type = XTERMCC_MULTITOKEN_END;
                } else {
                    result.string = [[[NSString alloc] initWithData:data
                                                           encoding:encoding] autorelease];
                    result->type = [self tokenTypeForMode:mode];
                    DLog(@"Finished parsing, returning type=%d", result->type);
                    if (result->type == XTERMCC_SET_KVP) {
                        [self parseKeyValuePairInToken:result];
                    }
                }
                return;

            case kXtermParserOutOfDataState:
                if (data.length && multitokenHeaderEmitted) {
                    DLog(@"Emitting body incidental with data=%@", data);
                    [self emitIncidentalForMultitokenBodyInVector:incidentals
                                                             data:data
                                                         encoding:encoding];
                    [data setLength:0];
                }
                savedState[kXtermParserSavedStateDataKey] = data;
                savedState[kXtermParserSavedStateBytesUsedKey] = @(iTermParserNumberOfBytesConsumed(context));
                savedState[kXtermParserSavedStateModeKey] = @(mode);
                savedState[kXtermParserSavedStateStateKey] = @(previousState);
                savedState[kXtermParserMultitokenHeaderEmittedkey] = @(multitokenHeaderEmitted);
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
        key = [argument substringToIndex:eqRange.location];
        value = [argument substringFromIndex:eqRange.location+1];
    } else {
        key = argument;
        value = @"";
    }

    token.kvpKey = key;
    token.kvpValue = value;
}

@end
