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

#import "iTerm2SharedARC-Swift.h"
#import "DebugLogging.h"
#import "NSStringITerm.h"
#import "VT100SixelParser.h"
#import "VT100StateMachine.h"
#import "VT100TmuxParser.h"

// Caps the amount of data to accumulate in _data before returning to the ground state. Prevents
// a random ESC P from eating output forever by leaving us in the passthrough state until we get
// an ST. Note that there's an exception for file downloads wrapped in DCS tmux; … ST
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

    // Holds the current state and the fine state machine. Up to one of these will be nonnull.
    VT100StateMachine *_stateMachineWithout8BitControlCharacters;
    VT100StateMachine *_stateMachineWith8BitControlCharacters;

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

    BOOL _support8BitControlCharacters;

    // We periodically check if _data looks like binary garbage. To avoid quadratic runtime we
    // remember the number of UTF-16 codepoints that have been checked already.
    NSInteger _checkedCount;
}

+ (NSDictionary *)termcapTerminfoNameDictionary {
    return @{ @"TN": @(kDcsTermcapTerminfoRequestTerminalName),
              @"name": @(kDcsTermcapTerminfoRequestTerminfoName),
              @"iTerm2Profile": @(kDcsTermcapTerminfoRequestiTerm2ProfileName),
              @"Co": @(kDcsTermcapTerminfoRequestNumberOfColors),
              @"colors": @(kDcsTermcapTerminfoRequestNumberOfColors2),
              @"RGB": @(kDcsTermcapTerminfoRequestDirectColorWidth),

              @"kb": @(kDcsTermcapTerminfoRequestKey_kb),
              @"kD": @(kDcsTermcapTerminfoRequestKey_kD),
              @"kd": @(kDcsTermcapTerminfoRequestKey_kd),
              @"@7": @(kDcsTermcapTerminfoRequestKey_at_7),
              @"@8": @(kDcsTermcapTerminfoRequestKey_at_8),
              @"k1": @(kDcsTermcapTerminfoRequestKey_k1),
              @"k2": @(kDcsTermcapTerminfoRequestKey_k2),
              @"k3": @(kDcsTermcapTerminfoRequestKey_k3),
              @"k4": @(kDcsTermcapTerminfoRequestKey_k4),
              @"k5": @(kDcsTermcapTerminfoRequestKey_k5),
              @"k6": @(kDcsTermcapTerminfoRequestKey_k6),
              @"k7": @(kDcsTermcapTerminfoRequestKey_k7),
              @"k8": @(kDcsTermcapTerminfoRequestKey_k8),
              @"k9": @(kDcsTermcapTerminfoRequestKey_k9),
              @"k;": @(kDcsTermcapTerminfoRequestKey_k_semi),
              @"F1": @(kDcsTermcapTerminfoRequestKey_F1),
              @"F2": @(kDcsTermcapTerminfoRequestKey_F2),
              @"F3": @(kDcsTermcapTerminfoRequestKey_F3),
              @"F4": @(kDcsTermcapTerminfoRequestKey_F4),
              @"F5": @(kDcsTermcapTerminfoRequestKey_F5),
              @"F6": @(kDcsTermcapTerminfoRequestKey_F6),
              @"F7": @(kDcsTermcapTerminfoRequestKey_F7),
              @"F8": @(kDcsTermcapTerminfoRequestKey_F8),
              @"F9": @(kDcsTermcapTerminfoRequestKey_F9),
              @"kh": @(kDcsTermcapTerminfoRequestKey_kh),
              @"kl": @(kDcsTermcapTerminfoRequestKey_kl),
              @"kN": @(kDcsTermcapTerminfoRequestKey_kN),
              @"kP": @(kDcsTermcapTerminfoRequestKey_kP),
              @"kr": @(kDcsTermcapTerminfoRequestKey_kr),
              @"*4": @(kDcsTermcapTerminfoRequestKey_star_4),
              @"*7": @(kDcsTermcapTerminfoRequestKey_star_7),
              @"#2": @(kDcsTermcapTerminfoRequestKey_pound_2),
              @"#4": @(kDcsTermcapTerminfoRequestKey_pound_4),
              @"%i": @(kDcsTermcapTerminfoRequestKey_pct_i),
              @"ku": @(kDcsTermcapTerminfoRequestKey_ku),
    };
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

// Defines the state machine.
- (VT100StateMachine *)stateMachine {
    if (_support8BitControlCharacters) {
        if (!_stateMachineWith8BitControlCharacters) {
            _stateMachineWith8BitControlCharacters = [self newStateMachineWith8BitControlCharacters:YES];
            _stateMachineWithout8BitControlCharacters = nil;
        }
        return _stateMachineWith8BitControlCharacters;
    }

    if (!_stateMachineWithout8BitControlCharacters) {
        _stateMachineWithout8BitControlCharacters = [self newStateMachineWith8BitControlCharacters:YES];
        _stateMachineWith8BitControlCharacters = nil;
    }
    return _stateMachineWithout8BitControlCharacters;
}

- (VT100StateMachine *)newStateMachineWith8BitControlCharacters:(BOOL)support8BitControlCharacters {
    VT100StateMachine *stateMachine = [[VT100StateMachine alloc] init];

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

    __weak __typeof(self) weakSelf = self;
    for (VT100State *state in stateMachine.states) {
        [state addStateTransitionForCharacter:VT100CC_CAN
                                           to:groundState
                                   withAction:^(unsigned char c) { [weakSelf execute]; } ];
        [state addStateTransitionForCharacter:VT100CC_SUB
                                           to:groundState
                                   withAction:^(unsigned char c) { [weakSelf execute]; } ];
        [state addStateTransitionForCharacter:VT100CC_ESC
                                           to:dcsEscapeState
                                   withAction:nil ];
        if (support8BitControlCharacters) {
            [state addStateTransitionForCharacterRange:MakeCharacterRange(VT100CC_C1_IND, VT100CC_C1_APC)
                                                    to:groundState
                                            withAction:^(unsigned char c) { [weakSelf execute]; } ];
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Add transitions from ground state.
    [groundState addStateTransitionForCharacter:VT100CC_ESC
                                             to:escapeState
                                     withAction:nil];
    if (support8BitControlCharacters) {
        [groundState addStateTransitionForCharacter:VT100CC_C1_DCS
                                                 to:dcsEntryState
                                         withAction:nil];
    }

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
        __strong __typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf->_malformed = NO;
            strongSelf->_executed = NO;
            [strongSelf->_data setString:@""];
            strongSelf->_checkedCount = 0;
            [strongSelf->_parameterString setString:@""];
            [strongSelf->_intermediateString setString:@""];
            [strongSelf->_privateMarkers setString:@""];
        }
    };
    // Got initial passthrough. Entry action will save it.
    [dcsEntryState addStateTransitionForCharacterRange:MakeCharacterRange('@', '~')
                                                    to:dcsPassthroughState
                                            withAction:nil];
    // Got an intermediate character. No parameter or private char will be found.
    [dcsEntryState addStateTransitionForCharacterRange:MakeCharacterRange(' ', '/')
                                                    to:dcsIntermediateState
                                            withAction:^(unsigned char c) {
                                                __strong __typeof(self) strongSelf = weakSelf;
                                                if (strongSelf) {
                                                    [strongSelf->_intermediateString appendCharacter:c];
                                                }
                                            }];
    // Transition to parameter string.
    [dcsEntryState addStateTransitionForCharacterRange:MakeCharacterRange('0', '9')
                                                    to:dcsParamState
                                            withAction:^(unsigned char c) {
                                                __strong __typeof(self) strongSelf = weakSelf;
                                                if (strongSelf) {
                                                    [strongSelf->_parameterString appendCharacter:c];
                                                }
                                            }];
    // Private char; parameter string must follow.
    [dcsEntryState addStateTransitionForCharacterRange:MakeCharacterRange('<', '?')
                                                    to:dcsParamState
                                            withAction:^(unsigned char c) {
                                                __strong __typeof(self) strongSelf = weakSelf;
                                                if (strongSelf) {
                                                    [strongSelf->_privateMarkers appendCharacter:c];
                                                }
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
                                                       __strong __typeof(self) strongSelf = weakSelf;
                                                       if (strongSelf) {
                                                           [strongSelf->_intermediateString appendCharacter:c];
                                                       }
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
                                                __strong __typeof(self) strongSelf = weakSelf;
                                                if (strongSelf) {
                                                    [strongSelf->_intermediateString appendCharacter:c];
                                                }
                                            }];
    // Got a number, save it as a parameter.
    [dcsParamState addStateTransitionForCharacterRange:MakeCharacterRange('0', '9')
                                                    to:dcsParamState
                                            withAction:^(unsigned char c) {
                                                __strong __typeof(self) strongSelf = weakSelf;
                                                if (strongSelf) {
                                                    [strongSelf->_parameterString appendCharacter:c];
                                                }
                                            }];
    // Got a semicolon, save it as a parameter.
    [dcsParamState addStateTransitionForCharacter:';'
                                               to:dcsParamState
                                       withAction:^(unsigned char c) {
                                           __strong __typeof(self) strongSelf = weakSelf;
                                           if (strongSelf) {
                                               [strongSelf->_parameterString appendCharacter:c];
                                           }
                                       }];
    // Initial passthrough character. Entry action will save it.
    [dcsParamState addStateTransitionForCharacterRange:MakeCharacterRange('@', '~')
                                                    to:dcsPassthroughState
                                            withAction:nil];

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Add transitions from ignore state.
    // Only way out of ignore is ST.
    dcsIgnoreState.entryAction = ^(unsigned char c) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf->_malformed = YES;
        }
    };
    [dcsIgnoreState addStateTransitionForCharacter:VT100CC_ESC
                                                to:dcsEscapeState
                                        withAction:^(unsigned char character) {
                                            [weakSelf unhook];
                                        }];
    if (support8BitControlCharacters) {
        [dcsIgnoreState addStateTransitionForCharacter:VT100CC_C1_ST
                                                    to:groundState
                                            withAction:^(unsigned char c) {
                                                [weakSelf execute];
                                            }];
    }

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
                                            [weakSelf execute];
                                        }];

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Add transitions from passthrough state.

    // On entry to passthrough, save the initial character. Note that there could be ESC characters
    // that cause us to re-enter passthrough after having already been in it so don't do anything
    // destructive here.
    dcsPassthroughState.entryAction = ^(unsigned char c) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf->_data appendCharacter:c];
            if (!strongSelf->_hook) {
                [strongSelf hook];
            }
        }
    };
    [dcsPassthroughState addStateTransitionForCharacterRange:MakeCharacterRange(VT100CC_NULL,
                                                                                VT100CC_ETB)
                                                          to:dcsPassthroughState
                                                  withAction:^(unsigned char c) {
                                                      [weakSelf put:c];
                                                  }];
    [dcsPassthroughState addStateTransitionForCharacter:VT100CC_EM
                                                     to:dcsPassthroughState
                                             withAction:^(unsigned char c) {
                                                 [weakSelf put:c];
                                             }];
    [dcsPassthroughState addStateTransitionForCharacterRange:MakeCharacterRange(VT100CC_FS,
                                                                                VT100CC_US)
                                                          to:dcsPassthroughState
                                                  withAction:^(unsigned char c) {
                                                      [weakSelf put:c];
                                                  }];
    [dcsPassthroughState addStateTransitionForCharacterRange:MakeCharacterRange(' ', '~')
                                                          to:dcsPassthroughState
                                                  withAction:^(unsigned char c) {
                                                      [weakSelf put:c];
                                                  }];
    if (support8BitControlCharacters) {
        [dcsPassthroughState addStateTransitionForCharacter:VT100CC_C1_ST
                                                         to:groundState
                                                 withAction:^(unsigned char c) {
                                                     [weakSelf execute];
                                                 }];
    }

    stateMachine.groundState = groundState;
    return stateMachine;
}

// Retrieve the token from the state machine's user info dictionary.
- (VT100Token *)token {
    return self.stateMachine.userInfo[kVT100DCSUserInfoToken];
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
        garbageCharacterSet = characterSet;
    });
    NSInteger offset = MAX(0, _checkedCount);
    const NSInteger limit = _data.length;
    if (offset > limit) {
        offset = MAX(0, limit);
    }
    _checkedCount = limit;
    NSInteger maxLength = kMaxDataLength;
    if ([_data hasPrefix:@"tmux;\e]1337;File="]) {
        // Allow file downloads to get really big.
        maxLength = NSIntegerMax;
    }
    return (_data.length > maxLength ||
            [_data rangeOfCharacterFromSet:garbageCharacterSet
                                   options:0
                                     range:NSMakeRange(offset, limit - offset)].location != NSNotFound);
}

- (void)decodeFromContext:(iTermParserContext *)context
                    token:(VT100Token *)result
                 encoding:(NSStringEncoding)encoding
               savedState:(NSMutableDictionary *)savedState {
    DLog(@"DCS parser running");
    _support8BitControlCharacters = (encoding == NSASCIIStringEncoding || encoding == NSISOLatin1StringEncoding);
    static NSString *const kOffset = @"offset";
    if (savedState[kOffset]) {
        iTermParserAdvanceMultiple(context, [savedState[kOffset] intValue]);
    }
    self.stateMachine.userInfo = @{ kVT100DCSUserInfoToken: result };
    result->type = VT100_WAIT;
    BOOL blocked = NO;
    while (result->type == VT100_WAIT && iTermParserCanAdvance(context) && !blocked) {
        if (_hook && !_hookFinished) {
            DLog(@"Sending input to hook %@ with context %@", _hook, iTermParserDebugString(context));
            const VT100DCSParserHookResult hookResult = [_hook handleInput:context
                                              support8BitControlCharacters:_support8BitControlCharacters
                                                                     token:result];
            switch (hookResult) {
                case VT100DCSParserHookResultBlocked:
                    _hookFinished = NO;
                    blocked = YES;
                    break;
                case VT100DCSParserHookResultCanReadAgain:
                    _hookFinished = NO;
                    break;
                case VT100DCSParserHookResultUnhook:
                    _hookFinished = YES;
                    [self unhook];
                    break;
            }
            DLog(@"Hook %@ produced %@: %@", [_hook hookDescription], @(hookResult), result);
        } else {
            [self.stateMachine handleCharacter:iTermParserConsume(context)];
            if ([self.stateMachine.currentState.identifier isEqual:@(kVT100DCSStatePassthrough)] &&
                [self dataLooksLikeBinaryGarbage]) {
                result->type = VT100_BINARY_GARBAGE;
            }
        }
        if (self.stateMachine.currentState == self.stateMachine.groundState) {
            break;
        }
    }

    self.stateMachine.userInfo = nil;

    if (self.stateMachine.currentState != self.stateMachine.groundState) {
        if (result->type == VT100_WAIT && !_hook) {
            savedState[kOffset] = @(iTermParserNumberOfBytesConsumed(context));
            iTermParserBacktrack(context);
        } else {
            [savedState removeAllObjects];
        }
    }
}

// Only add to this if you're doing something fancy. You can usually add your case to -execute
// instead.
- (void)hook {
    switch ([self compactSequence]) {
    case MAKE_COMPACT_SEQUENCE(0, 0, 'p'):
        if ([[self parameters] isEqual:@[ @"1000" ]]) {
            VT100Token *token = self.stateMachine.userInfo[kVT100DCSUserInfoToken];
            if (token) {
                token->type = DCS_TMUX_HOOK;
                _uniqueID = [[[NSUUID UUID] UUIDString] copy];
                token.string = _uniqueID;
            }

            _hook = [[VT100TmuxParser alloc] init];
            _hookFinished = NO;
        } else if ([[self parameters] isEqual:@[ @"2000" ]]) {
            VT100Token *token = self.stateMachine.userInfo[kVT100DCSUserInfoToken];
            if (token) {
                token->type = DCS_SSH_HOOK;
                _uniqueID = [[[NSUUID UUID] UUIDString] copy];
                token.string = _uniqueID;
            }

            _hook = [[VT100ConductorParser alloc] initWithUniqueID:_uniqueID];
            _hookFinished = NO;
        }
        break;

        case MAKE_COMPACT_SEQUENCE(0, 0, 'q'): {
            VT100Token *token = self.stateMachine.userInfo[kVT100DCSUserInfoToken];
            if (token) {
                token->type = VT100_SKIP;
                _uniqueID = [[[NSUUID UUID] UUIDString] copy];
                token.string = _uniqueID;
            }

            _hook = [[VT100SixelParser alloc] initWithParameters:[self parameters]];
            _hookFinished = NO;
            break;
        }
    }
}

- (void)unhook {
    _hook = nil;
    _uniqueID = nil;
    [_parameterString deleteCharactersInRange:NSMakeRange(0, _parameterString.length)];
    self.stateMachine.currentState = self.stateMachine.groundState;
}

// Force the ground state. Used when force-quitting tmux mode.
- (void)reset {
    [self unhook];
    self.stateMachine.currentState = self.stateMachine.groundState;
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
        case MAKE_COMPACT_SEQUENCE(0, '+', 'q'): {  // ESC P + q Param ST
            [self parseTermcapTerminfoToken:token];
            return;
        }

        case MAKE_COMPACT_SEQUENCE(0, 0, 'p'):  // ESC P 1000 p
            if ([[self parameters] isEqual:@[ @"1000" ]]) {
                // This shouldn't happen.
                [self unhook];
                token->type = VT100_SKIP;
            }
            break;

        case MAKE_COMPACT_SEQUENCE(0, 0, 'q'):
            [self unhook];
            token->type = VT100_SKIP;
            break;

        case MAKE_COMPACT_SEQUENCE(0, 0, 't'):
            if ([_data hasPrefix:@"tmux;"]) {
                token->type = DCS_TMUX_CODE_WRAP;
                token.string = [_data substringFromIndex:5];
            }
            break;

        case MAKE_COMPACT_SEQUENCE('=', 0, 's'):  // ESC P = Param s
            if ([_parameterString isEqualToString:@"1"]) {
                token->type = DCS_BEGIN_SYNCHRONIZED_UPDATE;
            } else if ([_parameterString isEqualToString:@"2"]) {
                token->type = DCS_END_SYNCHRONIZED_UPDATE;
            }
            break;
        case MAKE_COMPACT_SEQUENCE(0, '$', 'q'):
            token->type = DCS_DECRQSS;
            token.string = [_data substringFromIndex:1];
            break;

        case MAKE_COMPACT_SEQUENCE(0, '$', 't'):  // ESC P Param $ t
            if ([_parameterString isEqualToString:@"1"]) {
                token->type = DCS_DECRSPS_DECCIR;
            } else if ([_parameterString isEqualToString:@"2"]) {
                token->type = DCS_DECRSPS_DECTABSR;
            } else {
                token->type = VT100_SKIP;
            }
            if (token->type != VT100_SKIP) {
                token.string = [_data substringFromIndex:1];
            }
            break;

        case MAKE_COMPACT_SEQUENCE(0, '+', 'p'): {
            NSString *term = [_data substringFromIndex:1];
            if (term.length == 0) {
                token->type = VT100_SKIP;
                break;
            }
            token->type = DCS_XTSETTCAP;
            token.string = term;
            break;
        }
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

// TODO: recovery mode for conductor/ssh
- (void)startTmuxRecoveryModeWithID:(NSString *)dcsID {
    // Put the state machine in the passthrough mode.
    char *fakeControlSequence = "\eP1000p";
    for (int i = 0; fakeControlSequence[i]; i++) {
        [self.stateMachine handleCharacter:fakeControlSequence[i]];
    }

    // Replace the hook with one in recovery mode.
    _hook = [[VT100TmuxParser alloc] initInRecoveryMode];
    _uniqueID = [dcsID copy];
    DLog(@"dcs parser code injected and parser hooked.");
}

- (void)cancelTmuxRecoveryMode {
    if ([_hook isKindOfClass:[VT100TmuxParser class]]) {
        DLog(@"unhook");
        [self unhook];
    }
}

- (void)startConductorRecoveryModeWithID:(NSString *)dcsID {
    // Put the state machine in the passthrough mode.
    char *fakeControlSequence = "\eP2000p";
    for (int i = 0; fakeControlSequence[i]; i++) {
        [self.stateMachine handleCharacter:fakeControlSequence[i]];
    }

    // Replace the hook with one in recovery mode.
    _hook = [VT100ConductorParser newRecoveryModeInstanceWithUniqueID:dcsID];
    _uniqueID = [dcsID copy];
    DLog(@"dcs parser code injected and parser hooked.");
}

- (void)cancelConductorRecoveryMode {
    if ([_hook isKindOfClass:[VT100ConductorParser class]]) {
        DLog(@"unhook");
        [self unhook];
    }
}

@end

@implementation VT100DCSParser (Testing)

- (VT100DCSState)state {
    return [(NSNumber *)self.stateMachine.currentState.identifier intValue];
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

NSString *VT100DCSNameForTerminfoRequest(DcsTermcapTerminfoRequestName code) {
    switch (code) {
        case kDcsTermcapTerminfoRequestUnrecognizedName:
            return @"unrecognized";
        case kDcsTermcapTerminfoRequestTerminalName:
            return @"terminal";
        case kDcsTermcapTerminfoRequestiTerm2ProfileName:
            return @"iTerm2 profile";
        case kDcsTermcapTerminfoRequestTerminfoName:
            return @"terminfo";
        case kDcsTermcapTerminfoRequestNumberOfColors:
            return @"colors";
        case kDcsTermcapTerminfoRequestNumberOfColors2:
            return @"colors";
        case kDcsTermcapTerminfoRequestDirectColorWidth:
            return @"color width";
        case kDcsTermcapTerminfoRequestKey_kb:
            return @"backspace key";
        case kDcsTermcapTerminfoRequestKey_kD:
            return @"delete-character key";
        case kDcsTermcapTerminfoRequestKey_kd:
            return @"down-arrow key";
        case kDcsTermcapTerminfoRequestKey_at_7:
            return @"end key";
        case kDcsTermcapTerminfoRequestKey_at_8:
            return @"enter/send key";
        case kDcsTermcapTerminfoRequestKey_k1:
            return @"F1 function key";
        case kDcsTermcapTerminfoRequestKey_k2:
            return @"F2 function key";
        case kDcsTermcapTerminfoRequestKey_k3:
            return @"F3 function key";
        case kDcsTermcapTerminfoRequestKey_k4:
            return @"F4 function key";
        case kDcsTermcapTerminfoRequestKey_k5:
            return @"F5 function key";
        case kDcsTermcapTerminfoRequestKey_k6:
            return @"F6 function key";
        case kDcsTermcapTerminfoRequestKey_k7:
            return @"F7 function key";
        case kDcsTermcapTerminfoRequestKey_k8:
            return @"F8 function key";
        case kDcsTermcapTerminfoRequestKey_k9:
            return @"F9 function key";
        case kDcsTermcapTerminfoRequestKey_k_semi:
            return @"F10 function key";
        case kDcsTermcapTerminfoRequestKey_F1:
            return @"F11 function key";
        case kDcsTermcapTerminfoRequestKey_F2:
            return @"F12 function key";
        case kDcsTermcapTerminfoRequestKey_F3:
            return @"F13 function key";
        case kDcsTermcapTerminfoRequestKey_F4:
            return @"F14 function key";
        case kDcsTermcapTerminfoRequestKey_F5:
            return @"F15 function key";
        case kDcsTermcapTerminfoRequestKey_F6:
            return @"F16 function key";
        case kDcsTermcapTerminfoRequestKey_F7:
            return @"F17 function key";
        case kDcsTermcapTerminfoRequestKey_F8:
            return @"F18 function key";
        case kDcsTermcapTerminfoRequestKey_F9:
            return @"F19 function key";
        case kDcsTermcapTerminfoRequestKey_kh:
            return @"home key";
        case kDcsTermcapTerminfoRequestKey_kl:
            return @"left-arrow key";
        case kDcsTermcapTerminfoRequestKey_kN:
            return @"next-page key";
        case kDcsTermcapTerminfoRequestKey_kP:
            return @"previous-page key";
        case kDcsTermcapTerminfoRequestKey_kr:
            return @"right-arrow key";
        case kDcsTermcapTerminfoRequestKey_star_4:
            return @"shifted delete-character key";
        case kDcsTermcapTerminfoRequestKey_star_7:
            return @"shifted end key";
        case kDcsTermcapTerminfoRequestKey_pound_2:
            return @"shifted home key";
        case kDcsTermcapTerminfoRequestKey_pound_4:
            return @"shifted left-arrow key";
        case kDcsTermcapTerminfoRequestKey_pct_i:
            return @"shifted right-arrow key";
        case kDcsTermcapTerminfoRequestKey_ku:
            return @"up-arrow key";
    }
}
