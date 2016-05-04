//
//  VT100DCSParser.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//
// DCS [private] [parameters] [intermediate] initial-passthrough [remainder-of-passthrough]
// private: One character from: < = > ?
// parameters: Semicolon-delimited optional numbers (e.g., 1;2;3 or 1;;3)
// intermediate: One or more character from: ! " # $ % & ' ( ) * + , - . /
// initial-passthrough: One character between @ and ~ inclusive
// remainder-of-passthrough: One or more characters between SP and ~ inclusive.
//
// We implement, approximately, the DCS-related parts of the state machine described here:
// http://www.vt100.net/emu/dec_ansi_parser
// The main departure is that tmux mode is terminated by %exit ST, and ST (or other escape
// sequences) may occur prior to its termination and should be interpreted literally.

#import "VT100DCSParser.h"
#import "DebugLogging.h"
#import "NSStringITerm.h"
#import "VT100StateMachine.h"
#import "VT100TmuxParser.h"

// Caps the amount of data to accumulate in _data before returning to the ground state. Prevents
// a random ESC P from eating output forever by leaving us in the passthrough state until we get
// an ST.
static const NSUInteger kMaxDataLength = 1024 * 1024;

// Creates a unique-enough encoding of a DCS sequence at compile time so it can
// be a case in a switch.
#define MAKE_COMPACT_SEQUENCE(private, intermediate, initialPassthrough) \
    (((private) << 16) | ((intermediate) << 8) | (initialPassthrough))

// Key in the state machine's userInfo dictionary that gives reference to the current VT100Token
// being populated.
static NSString *const kVT100DCSUserInfoToken = @"kVT100DCSUserInfoToken";

static NSRange MakeCharacterRange(unsigned char first, unsigned char lastInclusive) {
    return NSMakeRange(first, lastInclusive - first + 1);
}

@implementation VT100DCSParser {
    BOOL _malformed;  // The current parse has failed but we're waiting for a terminator.

    // The current token has already been executed. If -execute gets called again, don't do
    // anything. This can happen if you get ESC + letter (for example) after the
    // initial-passthrough character.
    BOOL _executed;

    // The hook has terminated. The |_hook| member will remain non-nil because that causes the
    // client to continue to pass all input to us. We expect to get an ST, and will then nil out
    // |_hook|. This is here only for the tmux workaround (and the tmux parser is the only hook).
    BOOL _hookFinished;

    // Holds the current state and the fine state machine.
    VT100StateMachine *_stateMachine;

    // Concatenation of passthrough characters. Not added to when a hook is present.
    NSMutableString *_data;

    // See the description of DCS at the top of this file for what these are.
    // Only the first character of privateMarkers and intermediateString is used.
    NSMutableString *_privateMarkers;
    NSMutableString *_intermediateString;
    NSMutableString *_parameterString;

    // If set, and _hookFinished is false, then all input is passed to the hook instead of the
    // state machine. This is a departure from how it's really "supposed" to work but our only hook
    // is for the buggy tmux protocol, which is not terminated by ST alone (only %exit followed by
    // ST).
    id<VT100DCSParserHook> _hook;
}

+ (NSDictionary *)termcapTerminfoNameDictionary {
    return @{ @"TN": @(kDcsTermcapTerminfoRequestTerminalName),
              @"name": @(kDcsTermcapTerminfoRequestTerminfoName),
              @"iTerm2Profile": @(kDcsTermcapTerminfoRequestiTerm2ProfileName) };
}

+ (NSDictionary *)termcapTerminfoInverseNameDictionary {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSDictionary *dict = [self termcapTerminfoNameDictionary];
    for (NSString *key in dict) {
        id value = dict[key];
        result[value] = key;
    }
    return result;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _data = [[NSMutableString alloc] init];
        _parameterString = [[NSMutableString alloc] init];
        _intermediateString = [[NSMutableString alloc] init];
        _privateMarkers = [[NSMutableString alloc] init];
        [self stateMachine];
    }
    return self;
}

- (void)dealloc {
    [_stateMachine release];
    [_data release];
    [_parameterString release];
    [_intermediateString release];
    [_privateMarkers release];
    [_hook release];
    [super dealloc];
}

// Defines the state machine.
- (VT100StateMachine *)stateMachine {
    if (_stateMachine) {
        return _stateMachine;
    }

    VT100StateMachine *stateMachine;

    stateMachine = [[VT100StateMachine alloc] init];

    // This is where we start and end.
    VT100State *groundState = [VT100State stateWithName:@"ground"
                                             identifier:@(kVT100DCSStateGround)];
    // Ground can go to escape state when ESC is received.
    VT100State *escapeState = [VT100State stateWithName:@"escape"
                                             identifier:@(kVT100DCSStateEscape)];

    // Upon ESC P, enter dcsEntryState.
    VT100State *dcsEntryState = [VT100State stateWithName:@"dcs entry"
                                               identifier:@(kVT100DCSStateEntry)];

    // Reading "intermediate" bytes.
    VT100State *dcsIntermediateState = [VT100State stateWithName:@"dcs intermediate"
                                        identifier:@(kVT100DCSStateIntermediate)];

    // Reading numeric parameters separated by semicolons.
    VT100State *dcsParamState = [VT100State stateWithName:@"dcs param"
                                 identifier:@(kVT100DCSStateParam)];

    // An illegal character was received; swallow up bytes til ST.
    VT100State *dcsIgnoreState = [VT100State stateWithName:@"dcs ignore"
                                  identifier:@(kVT100DCSStateIgnore)];

    // An ESC was received which might lead to termination or something else.
    VT100State *dcsEscapeState = [VT100State stateWithName:@"dcs escape"
                                                identifier:@(kVT100DCSStateDCSEscape)];

    // Either accumulating characters in |_data| or sending them to the hook. Because of the tmux
    // hook hackery (see comments for |_hookFinished|) this actually only accumulates passthrough
    // data. Some day if a well-behaved hook is added, this might change to redirect data to the
    // hook.
    VT100State *dcsPassthroughState = [VT100State stateWithName:@"dcs passthrough"
                                                     identifier:@(kVT100DCSStatePassthrough)];

    [stateMachine addState:dcsEntryState];
    [stateMachine addState:dcsIntermediateState];
    [stateMachine addState:dcsParamState];
    [stateMachine addState:dcsIgnoreState];
    [stateMachine addState:groundState];
    [stateMachine addState:escapeState];
    [stateMachine addState:dcsEscapeState];
    [stateMachine addState:dcsPassthroughState];

    for (VT100State *state in stateMachine.states) {
        [state addStateTransitionForCharacter:VT100CC_CAN
                                           to:groundState
                                   withAction:^(unsigned char c) { [self execute]; } ];
        [state addStateTransitionForCharacter:VT100CC_SUB
                                           to:groundState
                                   withAction:^(unsigned char c) { [self execute]; } ];
        [state addStateTransitionForCharacter:VT100CC_ESC
                                           to:dcsEscapeState
                                   withAction:nil ];
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Add transitions from ground state.
    [groundState addStateTransitionForCharacter:VT100CC_ESC
                                             to:escapeState
                                     withAction:nil];

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Add transitions from escape state.
    [escapeState addStateTransitionForCharacterRange:MakeCharacterRange(0, 255)
                                                  to:groundState
                                          withAction:^(unsigned char character) {
                                              // We shouldn't have been called unless there was a DCS.
                                              assert(false);
                                          }];
    [escapeState addStateTransitionForCharacter:'P'
                                             to:dcsEntryState
                                     withAction:nil];

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Add transitions from entry state.
    dcsEntryState.entryAction = ^(unsigned char c) {
        _malformed = NO;
        _executed = NO;
        [_data setString:@""];
        [_parameterString setString:@""];
        [_intermediateString setString:@""];
        [_privateMarkers setString:@""];
    };
    // Got initial passthrough. Entry action will save it.
    [dcsEntryState addStateTransitionForCharacterRange:MakeCharacterRange('@', '~')
                                                    to:dcsPassthroughState
                                            withAction:nil];
    // Got an intermediate character. No parameter or private char will be found.
    [dcsEntryState addStateTransitionForCharacterRange:MakeCharacterRange(' ', '/')
                                                    to:dcsIntermediateState
                                            withAction:^(unsigned char c) {
                                                [_intermediateString appendCharacter:c];
                                            }];
    // Transition to parameter string.
    [dcsEntryState addStateTransitionForCharacterRange:MakeCharacterRange('0', '9')
                                                    to:dcsParamState
                                            withAction:^(unsigned char c) {
                                                [_parameterString appendCharacter:c];
                                            }];
    // Private char; parameter string must follow.
    [dcsEntryState addStateTransitionForCharacterRange:MakeCharacterRange('<', '?')
                                                    to:dcsParamState
                                            withAction:^(unsigned char c) {
                                                [_privateMarkers appendCharacter:c];
                                            }];
    // Colon is not allowed here.
    [dcsEntryState addStateTransitionForCharacter:':'
                                               to:dcsIgnoreState
                                       withAction:nil];


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Add transitions from intermediate state.
    // Got another intermediate character.
    [dcsIntermediateState addStateTransitionForCharacterRange:MakeCharacterRange(' ', '/')
                                                           to:dcsIntermediateState
                                                   withAction:^(unsigned char c) {
                                                       [_intermediateString appendCharacter:c];
                                                   }];
    // Illegal characters; swallow them up til we get a terminator in the ignore state.
    [dcsIntermediateState addStateTransitionForCharacterRange:MakeCharacterRange('0', '?')
                                                           to:dcsIgnoreState
                                                   withAction:nil];
    // Got an initial passthrough. Its entry action will save it.
    [dcsIntermediateState addStateTransitionForCharacterRange:MakeCharacterRange('@', '~')
                                                           to:dcsPassthroughState
                                                   withAction:nil];

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Add transitions from param state.
    // Not allowed. Swallow up illegal chars til terminator.
    [dcsParamState addStateTransitionForCharacter:':'
                                               to:dcsIgnoreState
                                       withAction:nil];
    [dcsParamState addStateTransitionForCharacterRange:MakeCharacterRange('<', '?')
                                                    to:dcsIgnoreState
                                            withAction:nil];
    // Got an intermediate character. Start reading intermediates.
    [dcsParamState addStateTransitionForCharacterRange:MakeCharacterRange(' ', '/')
                                                    to:dcsIntermediateState
                                            withAction:^(unsigned char c) {
                                                [_intermediateString appendCharacter:c];
                                            }];
    // Got a number, save it as a parameter.
    [dcsParamState addStateTransitionForCharacterRange:MakeCharacterRange('0', '9')
                                                    to:dcsParamState
                                            withAction:^(unsigned char c) {
                                                [_parameterString appendCharacter:c];
                                            }];
    // Got a semicolon, save it as a parameter.
    [dcsParamState addStateTransitionForCharacter:';'
                                               to:dcsParamState
                                       withAction:^(unsigned char c) {
                                           [_parameterString appendCharacter:c];
                                       }];
    // Initial passthrough character. Entry action will save it.
    [dcsParamState addStateTransitionForCharacterRange:MakeCharacterRange('@', '~')
                                                    to:dcsPassthroughState
                                            withAction:nil];

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Add transitions from ignore state.
    // Only way out of ignore is ST.
    dcsIgnoreState.entryAction = ^(unsigned char c) { _malformed = YES; };
    [dcsIgnoreState addStateTransitionForCharacter:VT100CC_ESC
                                                to:dcsEscapeState
                                        withAction:^(unsigned char character) {
                                            [self unhook];
                                        }];

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Add transitions from dcs escape state.

    // Escape + anything other than backslash returns to passthrough state. This is necessary to
    // handle doubled-up escapes in DCS tmux; nested-escape-sequence ST, where
    // nested-escape-sequence is a control sequence to pass through to the terminal with every ESC
    // replaced with ESC ESC. Passthrough's entry action will append it to _data.
    [dcsEscapeState addStateTransitionForCharacterRange:MakeCharacterRange(0, 255)
                                                     to:dcsPassthroughState
                                             withAction:nil];
    // ST. Try to execute the token.
    [dcsEscapeState addStateTransitionForCharacter:'\\'
                                                to:groundState
                                        withAction:^(unsigned char c) {
                                            [self execute];
                                        }];

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Add transitions from passthrough state.

    // On entry to passthrough, save the initial character. Note that there could be ESC characters
    // that cause us to re-enter passthrough after having already been in it so don't do anything
    // destructive here.
    dcsPassthroughState.entryAction = ^(unsigned char c) {
        [_data appendCharacter:c];
        if (!_hook) {
            [self hook];
        }
    };
    [dcsPassthroughState addStateTransitionForCharacterRange:MakeCharacterRange(VT100CC_NULL,
                                                                                VT100CC_ETB)
                                                          to:dcsPassthroughState
                                                  withAction:^(unsigned char c) {
                                                      [self put:c];
                                                  }];
    [dcsPassthroughState addStateTransitionForCharacter:VT100CC_EM
                                                     to:dcsPassthroughState
                                             withAction:^(unsigned char c) {
                                                 [self put:c];
                                             }];
    [dcsPassthroughState addStateTransitionForCharacterRange:MakeCharacterRange(VT100CC_FS,
                                                                                VT100CC_US)
                                                          to:dcsPassthroughState
                                                  withAction:^(unsigned char c) {
                                                      [self put:c];
                                                  }];
    [dcsPassthroughState addStateTransitionForCharacterRange:MakeCharacterRange(' ', '~')
                                                          to:dcsPassthroughState
                                                  withAction:^(unsigned char c) {
                                                      [self put:c];
                                                  }];

    _stateMachine = stateMachine;
    _stateMachine.groundState = groundState;
    return stateMachine;
}

// Retrieve the token from the state machine's user info dictionary.
- (VT100Token *)token {
    return _stateMachine.userInfo[kVT100DCSUserInfoToken];
}

// Save a passthrough character. If the tmux hack weren't here, it would direct to the hook if one
// were present.
- (void)put:(unsigned char)c {
    [_data appendCharacter:c];
}

- (BOOL)isHooked {
    return _hook != nil;
}

- (NSString *)hookDescription {
    return [_hook hookDescription];
}

- (BOOL)dataLooksLikeBinaryGarbage {
    static NSCharacterSet *garbageCharacterSet;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // This causes us to stop parsing DCS at a newline, which I hope is mostly harmless. But if
        // it's not, add 10 and 13 to this character set.
        NSMutableCharacterSet *characterSet = [NSMutableCharacterSet characterSetWithRange:NSMakeRange(32, 127 - 32)];
        [characterSet addCharactersInRange:NSMakeRange(VT100CC_ESC, 1)];
        // Keep going at BEL because the tmux OSC wrapper DCS tmux; OSC with double-escapes ST
        // could end in a BEL.
        [characterSet addCharactersInRange:NSMakeRange(VT100CC_BEL, 1)];
        [characterSet invert];
        garbageCharacterSet = [characterSet retain];
    });
    return (_data.length > kMaxDataLength ||
            [_data rangeOfCharacterFromSet:garbageCharacterSet].location != NSNotFound);
}

- (void)decodeFromContext:(iTermParserContext *)context
                    token:(VT100Token *)result
                 encoding:(NSStringEncoding)encoding
               savedState:(NSMutableDictionary *)savedState {
    DLog(@"DCS parser running");
    static NSString *const kOffset = @"offset";
    if (savedState[kOffset]) {
        iTermParserAdvanceMultiple(context, [savedState[kOffset] intValue]);
    }
    _stateMachine.userInfo = @{ kVT100DCSUserInfoToken: result };
    result->type = VT100_WAIT;
    while (result->type == VT100_WAIT && iTermParserCanAdvance(context)) {
        if (_hook && !_hookFinished) {
            DLog(@"Sending input to hook %@", _hook);
            _hookFinished = [_hook handleInput:context token:result];
        } else {
            [_stateMachine handleCharacter:iTermParserConsume(context)];
            if ([_stateMachine.currentState.identifier isEqual:@(kVT100DCSStatePassthrough)] &&
                [self dataLooksLikeBinaryGarbage]) {
                result->type = VT100_BINARY_GARBAGE;
            }
        }
        if (_stateMachine.currentState == _stateMachine.groundState) {
            break;
        }
    }

    _stateMachine.userInfo = nil;

    if (_stateMachine.currentState != _stateMachine.groundState) {
        if (result->type == VT100_WAIT && !_hook) {
            savedState[kOffset] = @(iTermParserNumberOfBytesConsumed(context));
            iTermParserBacktrack(context);
        } else {
            [savedState removeAllObjects];
        }
    }
}

- (void)hook {
    if ([self compactSequence] == MAKE_COMPACT_SEQUENCE(0, 0, 'p') &&
        [[self parameters] isEqual:@[ @"1000" ]]) {
        VT100Token *token = _stateMachine.userInfo[kVT100DCSUserInfoToken];
        if (token) {
            token->type = DCS_TMUX_HOOK;
        }

        [_hook release];
        _hook = [[VT100TmuxParser alloc] init];
        _hookFinished = NO;
    }
}

- (void)unhook {
    [_hook autorelease];
    _hook = nil;
}

// Force the ground state. Used when force-quitting tmux mode.
- (void)reset {
    [self unhook];
    _stateMachine.currentState = _stateMachine.groundState;
}

// Combines the private-mode character, intermediate character, and first
// character of passthrough into a unique integer.
- (int)compactSequence {
    char private = 0;
    char intermediate = 0;
    char initialPassthrough = 0;
    if (_privateMarkers.length) {
        private = [_privateMarkers characterAtIndex:0];
    }
    if (_intermediateString.length) {
        intermediate = [_intermediateString characterAtIndex:0];
    }
    if (_data.length) {
        initialPassthrough = [_data characterAtIndex:0];
    }
    return MAKE_COMPACT_SEQUENCE(private, intermediate, initialPassthrough);
}

// Called when the initial passthrough character is received to perhaps
// generate a token. Shouldn't be called if there's a hook.
- (void)execute {
    VT100Token *token = [self token];
    if (_malformed) {
        // Have entered the "dcs ignore" state.
        token->type = VT100_INVALID_SEQUENCE;
        [self unhook];
        return;
    }
    if (_executed) {
        NSLog(@"Warning: token already executed %@", token);
        return;
    }
    _executed = YES;
    token->type = VT100_NOTSUPPORT;
    switch ([self compactSequence]) {
        case MAKE_COMPACT_SEQUENCE(0, '+', 'q'): {
            [self parseTermcapTerminfoToken:token];
            return;
        }

        case MAKE_COMPACT_SEQUENCE(0, 0, 'p'):
            if ([[self parameters] isEqual:@[ @"1000" ]]) {
                // This shouldn't happen.
                [self unhook];
                token->type = VT100_SKIP;
            }
            break;

        case MAKE_COMPACT_SEQUENCE(0, 0, 't'):
            if ([_data hasPrefix:@"tmux;"]) {
                token->type = DCS_TMUX_CODE_WRAP;
                token.string = [_data substringFromIndex:5];
            }
            break;
    }
}

- (NSArray *)parameters {
    if (_parameterString.length) {
        return [_parameterString componentsSeparatedByString:@";"];
    } else {
        return @[];
    }
}

- (void)parseTermcapTerminfoToken:(VT100Token *)token {
    NSString *semicolonDelimitedHexEncodedNames = [_data substringFromIndex:1];
    NSArray *hexEncodedNames =
        [semicolonDelimitedHexEncodedNames componentsSeparatedByString:@";"];
    token->type = DCS_REQUEST_TERMCAP_TERMINFO;
    token.csi->count = 0;
    NSDictionary *nameMap = [[self class] termcapTerminfoNameDictionary];
    for (NSString *hexEncodedName in hexEncodedNames) {
        NSString *name = [NSString stringWithHexEncodedString:hexEncodedName];
        NSNumber *value = nameMap[name];
        if (value) {
            token.csi->p[token.csi->count++] = [value intValue];
        } else {
            token.csi->p[token.csi->count++] = kDcsTermcapTerminfoRequestUnrecognizedName;
        }
        if (token.csi->count == VT100CSIPARAM_MAX) {
            break;
        }
    }
}

- (void)startTmuxRecoveryMode {
    // Put the state machine in the passthrough mode.
    char *fakeControlSequence = "\eP1000p";
    for (int i = 0; fakeControlSequence[i]; i++) {
        [_stateMachine handleCharacter:fakeControlSequence[i]];
    }

    // Replace the hook with one in recovery mode.
    [_hook release];
    _hook = [[VT100TmuxParser alloc] initInRecoveryMode];
}

@end

@implementation VT100DCSParser (Testing)

- (VT100DCSState)state {
    return [(NSNumber *)_stateMachine.currentState.identifier intValue];
}

- (NSString *)data {
    return _data;
}

- (NSString *)intermediateString {
    return _intermediateString;
}

- (NSString *)privateMarkers {
    return _privateMarkers;
}

@end
