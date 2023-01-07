#import "VT100Output.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#import "iTermAdvancedSettingsModel.h"

#include <term.h>

#define MEDIAN(min_, mid_, max_) MAX(MIN(mid_, max_), min_)

// Indexes into _keyStrings.
typedef enum {
    TERMINFO_KEY_LEFT, TERMINFO_KEY_RIGHT, TERMINFO_KEY_UP, TERMINFO_KEY_DOWN,
    TERMINFO_KEY_HOME, TERMINFO_KEY_END, TERMINFO_KEY_PAGEDOWN,
    TERMINFO_KEY_PAGEUP, TERMINFO_KEY_F0, TERMINFO_KEY_F1, TERMINFO_KEY_F2,
    TERMINFO_KEY_F3, TERMINFO_KEY_F4, TERMINFO_KEY_F5, TERMINFO_KEY_F6,
    TERMINFO_KEY_F7, TERMINFO_KEY_F8, TERMINFO_KEY_F9, TERMINFO_KEY_F10,
    TERMINFO_KEY_F11, TERMINFO_KEY_F12, TERMINFO_KEY_F13, TERMINFO_KEY_F14,
    TERMINFO_KEY_F15, TERMINFO_KEY_F16, TERMINFO_KEY_F17, TERMINFO_KEY_F18,
    TERMINFO_KEY_F19, TERMINFO_KEY_F20, TERMINFO_KEY_F21, TERMINFO_KEY_F22,
    TERMINFO_KEY_F23, TERMINFO_KEY_F24, TERMINFO_KEY_F25, TERMINFO_KEY_F26,
    TERMINFO_KEY_F27, TERMINFO_KEY_F28, TERMINFO_KEY_F29, TERMINFO_KEY_F30,
    TERMINFO_KEY_F31, TERMINFO_KEY_F32, TERMINFO_KEY_F33, TERMINFO_KEY_F34,
    TERMINFO_KEY_F35, TERMINFO_KEY_BACKSPACE, TERMINFO_KEY_BACK_TAB,
    TERMINFO_KEY_TAB, TERMINFO_KEY_DEL, TERMINFO_KEY_INS, TERMINFO_KEY_HELP,
    TERMINFO_KEYS
} VT100TerminalTerminfoKeys;

typedef enum {
    // Keyboard modifier flags
    MOUSE_BUTTON_SHIFT_FLAG = 4,
    MOUSE_BUTTON_META_FLAG = 8,
    MOUSE_BUTTON_CTRL_FLAG = 16,

    // scroll flag
    MOUSE_BUTTON_SCROLL_FLAG = 64,  // this is a scroll event

    // extra buttons flag
    MOUSE_BUTTON_EXTRA_FLAG = 128,

} MouseButtonModifierFlag;

#define ESC  0x1b

// Codes to send for keypresses
#define CURSOR_SET_DOWN      "\033OB"
#define CURSOR_SET_UP        "\033OA"
#define CURSOR_SET_RIGHT     "\033OC"
#define CURSOR_SET_LEFT      "\033OD"
#define CURSOR_SET_HOME      "\033OH"
#define CURSOR_SET_END       "\033OF"
#define CURSOR_RESET_DOWN    "\033[B"
#define CURSOR_RESET_UP      "\033[A"
#define CURSOR_RESET_RIGHT   "\033[C"
#define CURSOR_RESET_LEFT    "\033[D"
#define CURSOR_RESET_HOME    "\033[H"
#define CURSOR_RESET_END     "\033[F"
#define CURSOR_MOD_DOWN      "\033[1;%dB"
#define CURSOR_MOD_UP        "\033[1;%dA"
#define CURSOR_MOD_RIGHT     "\033[1;%dC"
#define CURSOR_MOD_LEFT      "\033[1;%dD"
#define CURSOR_MOD_HOME      "\033[1;%dH"
#define CURSOR_MOD_END       "\033[1;%dF"

#define KEY_INSERT           "\033[2~"
#define KEY_PAGE_UP          "\033[5~"
#define KEY_PAGE_DOWN        "\033[6~"
#define KEY_DEL              "\033[3~"
#define KEY_BACKSPACE        "\010"

// Reporting formats
#define KEY_FUNCTION_FORMAT  @"\033[%d~"

#define REPORT_POSITION      "\033[%d;%dR"
#define REPORT_POSITION_Q    "\033[?%d;%dR"
#define REPORT_STATUS        "\033[0n"

// Secondary Device Attribute: VT100

#define STATIC_STRLEN(n)   ((sizeof(n)) - 1)

@implementation VT100Output {
    // Indexed by values in VT100TerminalTerminfoKeys.
    // Gives strings to send for various special keys.
    char *_keyStrings[TERMINFO_KEYS];

    // If $TERM is something normalish then we can do fancier key reporting
    // (e.g., modifier + forwards delete). When false, rely on terminfo's definition.
    BOOL _standard;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _optionIsMetaForSpecialKeys = YES;
        self.termType = @"dumb";
    }
    return self;
}

- (instancetype)initWithOutput:(VT100Output *)source {
    self = [super init];
    if (self) {
        for (int i = 0; i < TERMINFO_KEYS; i ++) {
            if (source->_keyStrings[i]) {
                _keyStrings[i] = strdup(source->_keyStrings[i]);
            }
        }
        _standard = source->_standard;
        _termType = [source->_termType copy];
        _keypadMode = source->_keypadMode;
        _mouseFormat = source->_mouseFormat;
        _cursorMode = source->_cursorMode;
        _optionIsMetaForSpecialKeys = source->_optionIsMetaForSpecialKeys;
        _vtLevel = source->_vtLevel;
    }
    return self;
}

- (NSDictionary *)configDictionary {
    return @{ @"termType": _termType ?: @"",
              @"keypadMode": @(_keypadMode),
              @"mouseFormat": @(_mouseFormat),
              @"cursorMode": @(_cursorMode),
              @"optionIsMetaForSpecialKeys": @(_optionIsMetaForSpecialKeys),
              @"vtLevel": @(_vtLevel)
    };
}

- (void)dealloc {
    for (int i = 0; i < TERMINFO_KEYS; i ++) {
        if (_keyStrings[i]) {
            free(_keyStrings[i]);
        }
    }
}

+ (NSSet<NSString *> *)standardTerminals {
    static NSSet<NSString *> *terms;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        terms = [NSSet setWithArray:@[ @"xterm",
                                       @"xterm-new",
                                       @"xterm-256color",
                                       @"xterm+256color",
                                       @"xterm-kitty",
                                       @"iterm",
                                       @"iterm2" ]];
    });
    return terms;
}

- (void)setTermType:(NSString *)term {
    _standard = [[VT100Output standardTerminals] containsObject:term];
    _termType = [term copy];
    int r = 0;
    setupterm((char *)[_termType UTF8String], fileno(stdout), &r);
    const BOOL termTypeIsValid = (r == 1);

    DLog(@"setTermTypeIsValid:%@ cur_term=%p", @(termTypeIsValid), cur_term);
    if (termTypeIsValid && cur_term) {
        char *key_names[] = {
            key_left, key_right, key_up, key_down,
            key_home, key_end, key_npage, key_ppage,
            key_f0, key_f1, key_f2, key_f3, key_f4,
            key_f5, key_f6, key_f7, key_f8, key_f9,
            key_f10, key_f11, key_f12, key_f13, key_f14,
            key_f15, key_f16, key_f17, key_f18, key_f19,
            key_f20, key_f21, key_f22, key_f23, key_f24,
            key_f25, key_f26, key_f27, key_f28, key_f29,
            key_f30, key_f31, key_f32, key_f33, key_f34,
            key_f35,
            key_backspace, key_btab,
            tab,
            key_dc, key_ic,
            key_help,
        };

        for (int i = 0; i < TERMINFO_KEYS; i ++) {
            if (_keyStrings[i]) {
                free(_keyStrings[i]);
            }
            _keyStrings[i] = key_names[i] ? strdup(key_names[i]) : NULL;
            DLog(@"Set key string %d (%s) to %s", i, key_names[i], _keyStrings[i]);
        }
    } else {
        for (int i = 0; i < TERMINFO_KEYS; i ++) {
            if (_keyStrings[i]) {
                free(_keyStrings[i]);
            }
            _keyStrings[i] = NULL;
        }
    }
}

- (NSData *)keyArrowUp:(unsigned int)modflag {
    return [self specialKey:TERMINFO_KEY_UP
                  cursorMod:CURSOR_MOD_UP
                  cursorSet:CURSOR_SET_UP
                cursorReset:CURSOR_RESET_UP
                    modflag:modflag
                   isCursor:YES];
}

- (NSData *)keyArrowDown:(unsigned int)modflag {
    return [self specialKey:TERMINFO_KEY_DOWN
                  cursorMod:CURSOR_MOD_DOWN
                  cursorSet:CURSOR_SET_DOWN
                cursorReset:CURSOR_RESET_DOWN
                    modflag:modflag
                   isCursor:YES];
}

- (NSData *)keyArrowLeft:(unsigned int)modflag {
    return [self specialKey:TERMINFO_KEY_LEFT
                  cursorMod:CURSOR_MOD_LEFT
                  cursorSet:CURSOR_SET_LEFT
                cursorReset:CURSOR_RESET_LEFT
                    modflag:modflag
                   isCursor:YES];
}

- (NSData *)keyArrowRight:(unsigned int)modflag {
    return [self specialKey:TERMINFO_KEY_RIGHT
                  cursorMod:CURSOR_MOD_RIGHT
                  cursorSet:CURSOR_SET_RIGHT
                cursorReset:CURSOR_RESET_RIGHT
                    modflag:modflag
                   isCursor:YES];
}

- (NSData *)keyHome:(unsigned int)modflag screenlikeTerminal:(BOOL)screenlike {
    if (screenlike) {
        const char *bytes = "\033[1~";
        return [NSData dataWithBytes:bytes length:strlen(bytes)];
    }
    return [self specialKey:TERMINFO_KEY_HOME
                  cursorMod:CURSOR_MOD_HOME
                  cursorSet:CURSOR_SET_HOME
                cursorReset:CURSOR_RESET_HOME
                    modflag:modflag
                   isCursor:NO];
}

- (NSData *)keyEnd:(unsigned int)modflag screenlikeTerminal:(BOOL)screenlike {
    if (screenlike) {
        const char *bytes = "\033[4~";
        return [NSData dataWithBytes:bytes length:strlen(bytes)];
    }
    return [self specialKey:TERMINFO_KEY_END
                  cursorMod:CURSOR_MOD_END
                  cursorSet:CURSOR_SET_END
                cursorReset:CURSOR_RESET_END
                    modflag:modflag
                   isCursor:NO];
}

- (NSData *)keyInsert {
    if (_keyStrings[TERMINFO_KEY_INS]) {
        return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_INS]
                              length:strlen(_keyStrings[TERMINFO_KEY_INS])];
    } else {
        return [NSData dataWithBytes:KEY_INSERT length:STATIC_STRLEN(KEY_INSERT)];
    }
}

- (NSData *)standardDataForKeyWithCode:(int)code flags:(NSEventModifierFlags)flags {
    if (!_standard) {
        return nil;
    }
    const int mod = [self cursorModifierParamForEventModifierFlags:flags];
    if (mod) {
        return [[NSString stringWithFormat:@"\e[%d;%d~", code, mod] dataUsingEncoding:NSUTF8StringEncoding];
    }
    return [[NSString stringWithFormat:@"\e[%d~", code] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)keyDelete:(NSEventModifierFlags)flags {
    NSData *standard = [self standardDataForKeyWithCode:3 flags:flags];
    if (standard) {
        return standard;
    }
    if (_keyStrings[TERMINFO_KEY_DEL]) {
        return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_DEL]
                              length:strlen(_keyStrings[TERMINFO_KEY_DEL])];
    } else {
        return [NSData dataWithBytes:KEY_DEL length:STATIC_STRLEN(KEY_DEL)];
    }
}

- (NSData *)keyBackspace {
    if (_keyStrings[TERMINFO_KEY_BACKSPACE]) {
        return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_BACKSPACE]
                              length:strlen(_keyStrings[TERMINFO_KEY_BACKSPACE])];
    } else {
        return [NSData dataWithBytes:KEY_BACKSPACE length:STATIC_STRLEN(KEY_BACKSPACE)];
    }
}

- (NSData *)keyPageUp:(unsigned int)modflag {
    NSData *standard = [self standardDataForKeyWithCode:5 flags:modflag];
    if (standard) {
        return standard;
    }
    NSData* theSuffix;
    if (_keyStrings[TERMINFO_KEY_PAGEUP]) {
        theSuffix = [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_PAGEUP]
                                   length:strlen(_keyStrings[TERMINFO_KEY_PAGEUP])];
    } else {
        theSuffix = [NSData dataWithBytes:KEY_PAGE_UP
                                   length:STATIC_STRLEN(KEY_PAGE_UP)];
    }
    NSMutableData* data = [NSMutableData data];
    if (modflag & NSEventModifierFlagOption) {
        char esc = ESC;
        [data appendData:[NSData dataWithBytes:&esc length:1]];
    }
    [data appendData:theSuffix];
    return data;
}

- (NSData *)keyPageDown:(unsigned int)modflag
{
    NSData *standard = [self standardDataForKeyWithCode:6 flags:modflag];
    if (standard) {
        return standard;
    }
    NSData* theSuffix;
    if (_keyStrings[TERMINFO_KEY_PAGEDOWN]) {
        theSuffix = [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_PAGEDOWN]
                                   length:strlen(_keyStrings[TERMINFO_KEY_PAGEDOWN])];
    } else {
        theSuffix = [NSData dataWithBytes:KEY_PAGE_DOWN
                                   length:STATIC_STRLEN(KEY_PAGE_DOWN)];
    }
    NSMutableData* data = [NSMutableData data];
    if (modflag & NSEventModifierFlagOption) {
        char esc = ESC;
        [data appendData:[NSData dataWithBytes:&esc length:1]];
    }
    [data appendData:theSuffix];
    return data;
}

- (BOOL)isLikeXterm {
    return [_termType hasPrefix:@"xterm"];
}

// https://invisible-island.net/xterm/xterm-function-keys.html hints at this but is incomplete.
// Much of this was determined by experimentation with xterm, TERM=xterm.
- (NSString *)xtermKeyFunction:(int)no modifiers:(NSEventModifierFlags)modifiers {
    // Modifiers remap function keys into higher number function keys, some of which probably
    // don't exist on any earthly keyboard.
    // regular f1 = f1          (+0)
    // meta f1 = f49            (+48)
    // control f1 = f25         (+24)
    // meta ctrl f1 = f75       (+74)
    // shift f1 = f13           (+12)
    // meta shift f1 = f61      (+60)
    // shift control f1 = f37   (+36)
    // meta shift ctrl f1 = f87 (+86)

    const BOOL shift = !!(modifiers & NSEventModifierFlagShift);
    const BOOL ctrl = !!(modifiers & NSEventModifierFlagControl);
    const BOOL meta = !!(modifiers & NSEventModifierFlagOption);

    const int offsets[] = {
             // Shift Control Meta
        0,   // no    no      no
        12,  // yes   no      no
        24,  // no    yes     no
        36,  // yes   yes     no
        48,  // no    no      yes
        60,  // yes   no      yes
        74,  // no    yes     yes
        86,  // yes   yes     yes
    };
    int i = 0;
    if (shift) {
        i += 1;
    }
    if (ctrl) {
        i += 2;
    }
    if (meta) {
        i += 4;
    }
    const int offset = offsets[i];

    switch (MEDIAN(1, no + offset, 98)) {
            // Regular
        case 1:
            return @"\eOP";
        case 2:
            return @"\eOQ";
        case 3:
            return @"\eOR";
        case 4:
            return @"\eOS";
        case 5:
            return @"\e[15~";
        case 6:
            return @"\e[17~";
        case 7:
            return @"\e[18~";
        case 8:
            return @"\e[19~";
        case 9:
            return @"\e[20~";
        case 10:
            return @"\e[21~";
        case 11:
            return @"\e[23~";
        case 12:
            return @"\e[24~";

            // shift
        case 13:
            return @"\e[1;2P";
        case 14:
            return @"\e[1;2Q";
        case 15:
            return @"\e[1;2R";
        case 16:
            return @"\e[1;2S";
        case 17:
            return @"\e[15;2~";
        case 18:
            return @"\e[17;2~";
        case 19:
            return @"\e[18;2~";
        case 20:
            return @"\e[19;2~";
        case 21:
            return @"\e[20;2~";
        case 22:
            return @"\e[21;2~";
        case 23:
            return @"\e[23;2~";
        case 24:
            return @"\e[24;2~";

            // control
        case 25:
            return @"\e[1;5P";
        case 26:
            return @"\e[1;5Q";
        case 27:
            return @"\e[1;5R";
        case 28:
            return @"\e[1;5S";
        case 29:
            return @"\e[15;5~";
        case 30:
            return @"\e[17;5~";
        case 31:
            return @"\e[18;5~";
        case 32:
            return @"\e[19;5~";
        case 33:
            return @"\e[20;5~";
        case 34:
            return @"\e[21;5~";
        case 35:
            return @"\e[23;5~";
        case 36:
            return @"\e[24;5~";

            // shift-control
        case 37:
            return @"\e[1;6P";
        case 38:
            return @"\e[1;6Q";
        case 39:
            return @"\e[1;6R";
        case 40:
            return @"\e[1;6S";
        case 41:
            return @"\e[15;6~";
        case 42:
            return @"\e[17;6~";
        case 43:
            return @"\e[18;6~";
        case 44:
            return @"\e[19;6~";
        case 45:
            return @"\e[20;6~";
        case 46:
            return @"\e[21;6~";
        case 47:
            return @"\e[23;6~";
        case 48:
            return @"\e[24;6~";

            // meta
        case 49:
            return _optionIsMetaForSpecialKeys ? @"\e[1;9P" : @"\e[1;3P";
        case 50:
            return _optionIsMetaForSpecialKeys ? @"\e[1;9Q" : @"\e[1;3Q";
        case 51:
            return _optionIsMetaForSpecialKeys ? @"\e[1;9R" : @"\e[1;3R";
        case 52:
            return _optionIsMetaForSpecialKeys ? @"\e[1;9S" : @"\e[1;3S";
        case 53:
            return _optionIsMetaForSpecialKeys ? @"\e[15;9~" : @"\e[15;3~";
        case 54:
            return _optionIsMetaForSpecialKeys ? @"\e[17;9~" : @"\e[17;3~";
        case 55:
            return _optionIsMetaForSpecialKeys ? @"\e[18;9~" : @"\e[18;3~";
        case 56:
            return _optionIsMetaForSpecialKeys ? @"\e[19;9~" : @"\e[19;3~";
        case 57:
            return _optionIsMetaForSpecialKeys ? @"\e[20;9~" : @"\e[20;3~";
        case 58:
            return _optionIsMetaForSpecialKeys ? @"\e[21;9~" : @"\e[21;3~";
        case 59:
            return _optionIsMetaForSpecialKeys ? @"\e[23;9~" : @"\e[23;3~";
        case 60:
            return _optionIsMetaForSpecialKeys ? @"\e[24;9~" : @"\e[24;3~";

            // shift-meta
        case 61:
            return _optionIsMetaForSpecialKeys ? @"\e[1;10P" : @"\e[1;4P";
        case 62:
            return _optionIsMetaForSpecialKeys ? @"\e[1;10Q" : @"\e[1;4Q";
        case 63:
            return _optionIsMetaForSpecialKeys ? @"\e[1;10R" : @"\e[1;4R";
        case 64:
            return _optionIsMetaForSpecialKeys ? @"\e[1;10S" : @"\e[1;4S";
        case 65:
            return _optionIsMetaForSpecialKeys ? @"\e[15;10~" : @"\e[15;4~";
        case 66:
            return _optionIsMetaForSpecialKeys ? @"\e[15;10~" : @"\e[15;4~";
        case 67:
            return _optionIsMetaForSpecialKeys ? @"\e[17;10~" : @"\e[17;4~";
        case 68:
            return _optionIsMetaForSpecialKeys ? @"\e[18;10~" : @"\e[18;4~";
        case 69:
            return _optionIsMetaForSpecialKeys ? @"\e[19;10~" : @"\e[19;4~";
        case 70:
            return _optionIsMetaForSpecialKeys ? @"\e[20;10~" : @"\e[20;4~";
        case 71:
            return _optionIsMetaForSpecialKeys ? @"\e[21;10~" : @"\e[21;4~";
        case 72:
            return _optionIsMetaForSpecialKeys ? @"\e[22;10~" : @"\e[22;4~";
        case 73:
            return _optionIsMetaForSpecialKeys ? @"\e[23;10~" : @"\e[23;4~";
        case 74:
            return _optionIsMetaForSpecialKeys ? @"\e[24;10~" : @"\e[24;4~";

            // control-meta
        case 75:
            return _optionIsMetaForSpecialKeys ? @"\e[1;13P" : @"\e[1;7P";
        case 76:
            return _optionIsMetaForSpecialKeys ? @"\e[1;13Q" : @"\e[1;7Q";
        case 77:
            return _optionIsMetaForSpecialKeys ? @"\e[1;13R" : @"\e[1;7R";
        case 78:
            return _optionIsMetaForSpecialKeys ? @"\e[1;13S" : @"\e[1;7S";
        case 79:
            return _optionIsMetaForSpecialKeys ? @"\e[15;13~" : @"\e[15;7~";
        case 80:
            return _optionIsMetaForSpecialKeys ? @"\e[17;13~" : @"\e[17;7~";
        case 81:
            return _optionIsMetaForSpecialKeys ? @"\e[18;13~" : @"\e[18;7~";
        case 82:
            return _optionIsMetaForSpecialKeys ? @"\e[19;13~" : @"\e[19;7~";
        case 83:
            return _optionIsMetaForSpecialKeys ? @"\e[20;13~" : @"\e[20;7~";
        case 84:
            return _optionIsMetaForSpecialKeys ? @"\e[21;13~" : @"\e[21;7~";
        case 85:
            return _optionIsMetaForSpecialKeys ? @"\e[23;13~" : @"\e[23;7~";
        case 86:
            return _optionIsMetaForSpecialKeys ? @"\e[24;13~" : @"\e[24;7~";

            // shift-control-meta
        case 87:
            return _optionIsMetaForSpecialKeys ? @"\e[1;14P" : @"\e[1;8P";
        case 88:
            return _optionIsMetaForSpecialKeys ? @"\e[1;14Q" : @"\e[1;8Q";
        case 89:
            return _optionIsMetaForSpecialKeys ? @"\e[1;14R" : @"\e[1;8R";
        case 90:
            return _optionIsMetaForSpecialKeys ? @"\e[1;14S" : @"\e[1;8S";
        case 91:
            return _optionIsMetaForSpecialKeys ? @"\e[15;14~" : @"\e[15;8~";
        case 92:
            return _optionIsMetaForSpecialKeys ? @"\e[17;14~" : @"\e[17;8~";
        case 93:
            return _optionIsMetaForSpecialKeys ? @"\e[18;14~" : @"\e[18;8~";
        case 94:
            return _optionIsMetaForSpecialKeys ? @"\e[19;14~" : @"\e[19;8~";
        case 95:
            return _optionIsMetaForSpecialKeys ? @"\e[20;14~" : @"\e[20;8~";
        case 96:
            return _optionIsMetaForSpecialKeys ? @"\e[21;14~" : @"\e[21;8~";
        case 97:
            return _optionIsMetaForSpecialKeys ? @"\e[23;14~" : @"\e[23;8~";
        case 98:
            return _optionIsMetaForSpecialKeys ? @"\e[24;14~" : @"\e[24;8~";
    }
    return nil;
}

- (NSData *)dataForStandardFunctionKeyWithCode:(int)code {
    return [[NSString stringWithFormat:KEY_FUNCTION_FORMAT, code] dataUsingEncoding:NSISOLatin1StringEncoding];
}

// Reference: http://www.utexas.edu/cc/faqs/unix/VT200-function-keys.html
// http://www.cs.utk.edu/~shuford/terminal/misc_old_terminals_news.txt
- (NSData *)keyFunction:(int)no modifiers:(NSEventModifierFlags)modifiers {
    DLog(@"keyFunction:%@", @(no));
    char str[256];
    int len;

    if ([self isLikeXterm]) {
        return [[self xtermKeyFunction:no modifiers:modifiers] dataUsingEncoding:NSISOLatin1StringEncoding];
    }

    if (no <= 5) {
        if (_keyStrings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_F0+no]
                                  length:strlen(_keyStrings[TERMINFO_KEY_F0+no])];
        } else {
            return [self dataForStandardFunctionKeyWithCode:no + 10];
        }
    } else if (no <= 10) {
        if (_keyStrings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_F0+no]
                                  length:strlen(_keyStrings[TERMINFO_KEY_F0+no])];
        } else {
            return [self dataForStandardFunctionKeyWithCode:no + 11];
        }
    } else if (no <= 14) {
        if (_keyStrings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_F0+no]
                                  length:strlen(_keyStrings[TERMINFO_KEY_F0+no])];
        } else {
            return [self dataForStandardFunctionKeyWithCode:no + 12];
        }
    } else if (no <= 16) {
        if (_keyStrings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_F0+no]
                                  length:strlen(_keyStrings[TERMINFO_KEY_F0+no])];
        } else {
            return [self dataForStandardFunctionKeyWithCode:no + 13];
        }
    } else if (no <= 20) {
        if (_keyStrings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_F0+no]
                                  length:strlen(_keyStrings[TERMINFO_KEY_F0+no])];
        } else {
            return [self dataForStandardFunctionKeyWithCode:no + 14];
        }
    } else if (no <= 35) {
        if (_keyStrings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_F0+no]
                                  length:strlen(_keyStrings[TERMINFO_KEY_F0+no])];
        } else {
            str[0] = 0;
        }
    } else {
        str[0] = 0;
    }
    len = strlen(str);
    return [NSData dataWithBytes:str length:len];
}

- (NSData *)keypadDataForString:(NSString *)keystr modifiers:(NSEventModifierFlags)modifiers {
    // Numeric keypad mode (regular).
    if (!self.keypadMode) {
        if ([keystr isEqualToString:@"\x03"]) {
            return [@"\r" dataUsingEncoding:NSUTF8StringEncoding];
        }
        return [keystr dataUsingEncoding:NSUTF8StringEncoding];
    }

    // Application keypad mode.
    const int mod = [self cursorModifierParamForEventModifierFlags:modifiers];
    NSString *modString = (mod == 0) ? @"" : [@(mod) stringValue];

    NSDictionary *dict = @{
        @"0": @"p",
        @"1": @"q",
        @"2": @"r",
        @"3": @"s",
        @"4": @"t",
        @"5": @"u",
        @"6": @"v",
        @"7": @"w",
        @"8": @"x",
        @"9": @"y",
        @"-": @"m",
        @"+": @"k",
        @".": @"n",
        @"/": @"o",
        @"*": @"j",
        @"=": @"X",
        @"\x03": @"M"
    };
    NSString *suffix = dict[keystr];
    if (!suffix) {
        return [keystr dataUsingEncoding:NSUTF8StringEncoding];
    }
    return [[NSString stringWithFormat:@"\eO%@%@", modString, suffix] dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)shouldReportMouseMotionAtCoord:(VT100GridCoord)coord
                             lastCoord:(VT100GridCoord)lastReportedCoord
                                 point:(NSPoint)point
                             lastPoint:(NSPoint)lastReportedPoint {
    switch (self.mouseFormat) {
        case MOUSE_FORMAT_SGR_PIXEL:
            DLog(@"pixel report. point=%@ last=%@", NSStringFromPoint(point), NSStringFromPoint(lastReportedPoint));
            return !NSEqualPoints(point, lastReportedPoint);
        case MOUSE_FORMAT_XTERM_EXT:
        case MOUSE_FORMAT_URXVT:
        case MOUSE_FORMAT_SGR:
        case MOUSE_FORMAT_XTERM:
        default:
            DLog(@"coord report. coord=%@ last=%@", VT100GridCoordDescription(coord),
                 VT100GridCoordDescription(lastReportedCoord));
            return !VT100GridCoordEquals(coord, lastReportedCoord);
    }
}

- (NSData *)mouseReport:(int)button coord:(VT100GridCoord)coord point:(NSPoint)point {
    return [self mouseReport:button release:false coord:coord point:point];
}

- (NSData *)mouseReport:(int)button release:(bool)release coord:(VT100GridCoord)coord point:(NSPoint)point {
    switch (self.mouseFormat) {
        case MOUSE_FORMAT_XTERM_EXT: {
            // TODO: This doesn't handle positions greater than 223 correctly. It should use UTF-8.
            NSString *string = [NSString stringWithFormat:@"\e[M%@%@%@",
                                [NSString stringWithLongCharacter:32 + button],
                                [NSString stringWithLongCharacter:32 + coord.x],
                                [NSString stringWithLongCharacter:32 + coord.y]];
            return [string dataUsingEncoding:NSUTF8StringEncoding];
        }
        case MOUSE_FORMAT_URXVT:
            return [[NSString stringWithFormat:@"\033[%d;%d;%dM", 32 + button, coord.x, coord.y]  dataUsingEncoding:NSUTF8StringEncoding];

        case MOUSE_FORMAT_SGR:
            return [[self reportForSGRButton:button release:release x:coord.x y:coord.y]  dataUsingEncoding:NSUTF8StringEncoding];

        case MOUSE_FORMAT_SGR_PIXEL:
            return [[self reportForSGRButton:button release:release x:point.x y:point.y]  dataUsingEncoding:NSUTF8StringEncoding];

        case MOUSE_FORMAT_XTERM:
        default:
            return [[NSString stringWithFormat:@"\033[M%c%c%c", 32 + button, MIN(255, 32 + coord.x), MIN(255, 32 + coord.y)] dataUsingEncoding:NSISOLatin1StringEncoding];
    }
    return [NSData data];
}

- (NSString *)reportForSGRButton:(int)button release:(bool)release x:(int)x y:(int)y {
    if (release) {
        // Mouse release event.
        return [NSString stringWithFormat:@"\033[<%d;%d;%dm",
                 button,
                 x,
                 y];
    }
    // Mouse press/motion event.
    return [NSString stringWithFormat:@"\033[<%d;%d;%dM", button, x, y];
}

static int VT100OutputDoubleToInt(double d) {
    const double rounded = round(d);
    if (rounded < INT_MIN) {
        return INT_MIN;
    }
    if (rounded > INT_MAX) {
        return INT_MAX;
    }
    return (int)rounded;
}

static int VT100OutputSafeAddInt(int l, int r) {
    long long temp = l;
    temp += r;
    if (temp < INT_MIN) {
        return INT_MIN;
    }
    if (temp > INT_MAX) {
        return INT_MAX;
    }
    return (int)temp;
}

- (NSData *)mousePress:(int)button withModifiers:(unsigned int)modflag at:(VT100GridCoord)coord point:(NSPoint)point {
    int cb;

    // convert x11 button number to terminal button code
    cb = button & 3;
    if (button == MOUSE_BUTTON_SCROLLDOWN || button == MOUSE_BUTTON_SCROLLUP ||
        button == MOUSE_BUTTON_SCROLLLEFT || button == MOUSE_BUTTON_SCROLLRIGHT) {
        cb |= MOUSE_BUTTON_SCROLL_FLAG;
    }
    if (button >= MOUSE_BUTTON_BACKWARD) {
        cb |= MOUSE_BUTTON_EXTRA_FLAG;
    }
    if (modflag & NSEventModifierFlagControl) {
        cb |= MOUSE_BUTTON_CTRL_FLAG;
    }
    if (modflag & NSEventModifierFlagShift) {
        cb |= MOUSE_BUTTON_SHIFT_FLAG;
    }
    if (modflag & NSEventModifierFlagCommand) {
        cb |= MOUSE_BUTTON_META_FLAG;
    }
    return [self mouseReport:cb
                       coord:VT100GridCoordMake((coord.x + 1),
                                                (coord.y + 1))
                       point:NSMakePoint(VT100OutputDoubleToInt(VT100OutputSafeAddInt(point.x, 1)),
                                         VT100OutputDoubleToInt(VT100OutputSafeAddInt(point.y, 1)))];
}

- (NSData *)mouseRelease:(int)button withModifiers:(unsigned int)modflag at:(VT100GridCoord)coord point:(NSPoint)point {
    int cb;

    // convert x11 button number to terminal button code
    cb = button & 3;
    if (self.mouseFormat != MOUSE_FORMAT_SGR && self.mouseFormat != MOUSE_FORMAT_SGR_PIXEL) {
        // for 1000/1005/1015 mode
        // To quote the xterm docs:
        // The low two bits of C b encode button information:
        // 0=MB1 pressed, 1=MB2 pressed, 2=MB3 pressed, 3=release.
        cb = 3;
    }

    if (button >= MOUSE_BUTTON_BACKWARD) {
        cb |= MOUSE_BUTTON_EXTRA_FLAG;
    }
    if (modflag & NSEventModifierFlagControl) {
        cb |= MOUSE_BUTTON_CTRL_FLAG;
    }
    if (modflag & NSEventModifierFlagShift) {
        cb |= MOUSE_BUTTON_SHIFT_FLAG;
    }
    if (modflag & NSEventModifierFlagCommand) {
        cb |= MOUSE_BUTTON_META_FLAG;
    }
    return [self mouseReport:cb
                       release:true
                       coord:VT100GridCoordMake(coord.x + 1,
                                                coord.y + 1)
                       point:NSMakePoint(VT100OutputDoubleToInt(VT100OutputSafeAddInt(point.x, 1)),
                                         VT100OutputDoubleToInt(VT100OutputSafeAddInt(point.y, 1)))];
}

- (NSData *)mouseMotion:(int)button withModifiers:(unsigned int)modflag at:(VT100GridCoord)coord point:(NSPoint)point {
    int cb;

    if (button == MOUSE_BUTTON_NONE) {
        cb = button;
    } else {
        cb = button % 3;
    }
    if (button == MOUSE_BUTTON_SCROLLDOWN || button == MOUSE_BUTTON_SCROLLUP ||
        button == MOUSE_BUTTON_SCROLLLEFT || button == MOUSE_BUTTON_SCROLLRIGHT) {
        cb |= MOUSE_BUTTON_SCROLL_FLAG;
    }
    if (button >= MOUSE_BUTTON_BACKWARD) {
        cb |= MOUSE_BUTTON_EXTRA_FLAG;
    }
    if (modflag & NSEventModifierFlagControl) {
        cb |= MOUSE_BUTTON_CTRL_FLAG;
    }
    if (modflag & NSEventModifierFlagShift) {
        cb |= MOUSE_BUTTON_SHIFT_FLAG;
    }
    if (modflag & NSEventModifierFlagCommand) {
        cb |= MOUSE_BUTTON_META_FLAG;
    }
    return [self mouseReport:(32 + cb)
                       coord:VT100GridCoordMake((coord.x + 1),
                                                (coord.y + 1))
                       point:NSMakePoint(VT100OutputDoubleToInt(VT100OutputSafeAddInt(point.x, 1)),
                                         VT100OutputDoubleToInt(VT100OutputSafeAddInt(point.y, 1)))];
}

- (NSData *)reportiTerm2Version {
    // We uppercase the string to ensure it does not contain a "n".
    // The [ must never be followed by a 0 (see the isiterm2.sh script for justification).
    NSString *version = [NSString stringWithFormat:@"%c[ITERM2 %@n", ESC,
                         [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] uppercaseString]];
    return [version dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportKeyReportingMode:(int)mode {
    return [[NSString stringWithFormat:@"%c[?%du", ESC, mode] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportActivePositionWithX:(int)x Y:(int)y withQuestion:(BOOL)q
{
    char buf[64];

    snprintf(buf, sizeof(buf), q?REPORT_POSITION_Q:REPORT_POSITION, y, x);

    return [NSData dataWithBytes:buf length:strlen(buf)];
}

- (NSData *)reportStatus
{
    return [NSData dataWithBytes:REPORT_STATUS
                          length:STATIC_STRLEN(REPORT_STATUS)];
}

- (NSData *)reportDeviceAttribute {
    // VT220 + sixel
    // For a very long time we returned 1;2, like most other terms, but we need to advertise sixel
    // support. Let's see what happens! New in version 3.3.0.
    //
    // Update: Per issue 7803, VT200 must accept 8-bit CSI. Allow users to elect VT100 reporting by
    // setting $TERM to VT100.
    //
    // The first value gives the "operating level":
    // 61 = vt100 family
    // 62 = vt200
    // 63 = vt300
    // 64 = vt400-vt510 (this is what xcode reports by default)
    // 65 = vt520+
    // xcode seems to report 64 and the vt510 docs give 64 as the operating level as well.

    // The following features are supported by xterm:
    //
    // 1: 132 columns
    // 2: Printer port
    // 3: ReGIS graphics
    // 4: Sixel graphics
    // 6: Selective erase
    // 8: User-defined keys (UDKs)
    // 9: National replacement character sets (NRCS)
    // 15: Technical character set
    // 16: Locator port  (this is like a mouse; see CSI 'z)
    // 17: Terminal state interrogation (see below)
    // 18: Windowing capability (I think this means you need to support rectangle operations and DECSLRM; xterm also mentions: DECSNLS, DECSCPP, DECSLPP)
    // 21: Horizontal scrolling (based on mintty I think this means the SL and SR codes)
    // 22: ANSI color, VT525 (the vt525 was a color version of the vt520)
    // 28: rectangular editing
    // 29: ANSI text locator

    // These are defined by DEC but not supported by xterm:
    // 7: Soft character set (DRCS)
    // 12: Serbo-Croatian (SCS)
    // 19: Sessions
    // 23: Greek
    // 24: Turkish
    // 42: ISO Latin-2
    // 44: PCTerm
    // 45: Soft key mapping
    // 46: ASCII terminal emulation


    typedef NS_ENUM(NSInteger, VT100OutputPrimaryDAFeature) {
        VT100OutputPrimaryDAFeature132Columns = 1,
        VT100OutputPrimaryDAFeaturePrinterPort = 2,
        VT100OutputPrimaryDAFeatureReGISGraphics = 3,
        VT100OutputPrimaryDAFeatureSixelGraphics = 4,
        VT100OutputPrimaryDAFeatureSelectiveErase = 6,
        VT100OutputPrimaryDAFeatureSoftCharacterSet = 7,
        VT100OutputPrimaryDAFeatureUserDefinedKeys = 8,
        VT100OutputPrimaryDAFeatureNationalReplacementCharacterSets = 9,
        VT100OutputPrimaryDAFeatureSerboCroatian = 12,
        VT100OutputPrimaryDAFeatureTechnicalCharacterSet = 15,
        VT100OutputPrimaryDAFeatureLocatorPort = 16,
        VT100OutputPrimaryDAFeatureTerminalStateInterrogation = 17,
        VT100OutputPrimaryDAFeatureWindowingCapability = 18,
        VT100OutputPrimaryDAFeatureSessions = 19,
        VT100OutputPrimaryDAFeatureHorizontalScrolling = 21,
        VT100OutputPrimaryDAFeatureANSIColor = 22,
        VT100OutputPrimaryDAFeatureGreek = 23,
        VT100OutputPrimaryDAFeatureTurkish = 24,
        VT100OutputPrimaryDAFeatureRectangularEditing = 28,
        VT100OutputPrimaryDAFeatureANSITextLocator = 29,
        VT100OutputPrimaryDAFeatureISOLatin2 = 42,
        VT100OutputPrimaryDAFeaturePCTerm = 44,
        VT100OutputPrimaryDAFeatureSoftKeyMapping = 45,
        VT100OutputPrimaryDAFeatureASCIITerminalEmulation = 46,

        VT100OutputPrimaryDAFeatureVT125 = 12,
        VT100OutputPrimaryDAFeatureVT220 = 62,
        VT100OutputPrimaryDAFeatureVT320 = 63,
        VT100OutputPrimaryDAFeatureVT420 = 64
    };

    VT100OutputPrimaryDAFeature vt100Features[] = {
        VT100OutputPrimaryDAFeature132Columns,
        VT100OutputPrimaryDAFeaturePrinterPort
    };
    VT100OutputPrimaryDAFeature vt200Features[] = {
        VT100OutputPrimaryDAFeatureVT220,
        VT100OutputPrimaryDAFeature132Columns,
        VT100OutputPrimaryDAFeaturePrinterPort,
        VT100OutputPrimaryDAFeatureSixelGraphics,
        VT100OutputPrimaryDAFeatureSelectiveErase,
        VT100OutputPrimaryDAFeatureANSIColor,
        VT100OutputPrimaryDAFeatureRectangularEditing

    };
    VT100OutputPrimaryDAFeature vt400Features[] = {
        VT100OutputPrimaryDAFeatureVT420,
        VT100OutputPrimaryDAFeature132Columns,
        VT100OutputPrimaryDAFeaturePrinterPort,
        VT100OutputPrimaryDAFeatureSixelGraphics,
        VT100OutputPrimaryDAFeatureSelectiveErase,
        VT100OutputPrimaryDAFeatureTerminalStateInterrogation,
        VT100OutputPrimaryDAFeatureWindowingCapability,
        VT100OutputPrimaryDAFeatureHorizontalScrolling,
        VT100OutputPrimaryDAFeatureANSIColor
    };

    // TERMINAL STATE INTERROGATION
    // I found a file called vt_function_list.pdf at http://web.mit.edu/dosathena/doc/www/vt_function_list.pdf
    // that describes the following codes as TSI (with modifications by me for elucidation):
    //
    // DECRQM - Request Mode [response: DECRPM - Report Mode]
    // DECNKM - Numeric Keypad Mode (DEC[RE]SET 66)
    // DECRQSS - Request Selection or Setting [response: DECRPSS - Report Selection or Setting]
    // DECRQPSR - Request Presentation State Report
    //   The response is DECPSR - Presentation State Report, which is one of:
    //     * DECCIR - Cursor Information Report
    //     * DECTABSR - Tabulation Stop Report]
    // DECRSPS - Restore Presentation State
    // DECRQTSR - Request Terminal State Report [response: DECTSR - Terminal State Report]
    //     NOTE: xterm does not implement this.
    //     The VT420 docs say:
    //         "DECTSR informs the host of the entire state of the terminal, except for user-defined
    //          key definitions and the current soft character set"
    //     and:
    //         "Software should not expect the format of DECTSR to be the same for all members of the
    //          VT400 family, or for different revisions within each member of the family."
    //     VT520 seems to have added a second function, a color table report, for DECRQTSR with parameter 2.
    // DECRSTS - Restore Terminal State
    //     NOTE: xterm does not implement this.
    //     NOTE: This restores state using the response from DECRQTSR.
    VT100OutputPrimaryDAFeature *features;
    size_t count;
    switch (_vtLevel) {
        case VT100EmulationLevel100:
            features = vt100Features;
            count = sizeof(vt100Features) / sizeof(*vt100Features);
            break;
        case VT100EmulationLevel200:
            features = vt200Features;
            count = sizeof(vt200Features) / sizeof(*vt200Features);
            break;
        case VT100EmulationLevel400:
            features = vt400Features;
            count = sizeof(vt400Features) / sizeof(*vt400Features);
            break;
    }
    NSString *params = [[[NSArray sequenceWithRange:NSMakeRange(0, count)] mapWithBlock:^id(NSNumber *anObject) {
        return [@(features[anObject.intValue]) stringValue];
    }] componentsJoinedByString:@";"];
    return [[NSString stringWithFormat:@"\033[?%@c", params] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportSecondaryDeviceAttribute {
    const int xtermVersion = [iTermAdvancedSettingsModel xtermVersion];
    int vt = 0;
    switch (_vtLevel) {
        case VT100EmulationLevel100:
            vt = 0;
            break;
        case VT100EmulationLevel200:
            vt = 1;
            break;
        case VT100EmulationLevel400:
            vt = 41;
            break;
    }
    // Beware of responding with 65 in the first position! Emacs will downgrade you for a response
    // with 65 in th4e first place and any value over 2000 in the second place. It's useful to
    // put 2500+ in the second place to trick vim into giving us undeline RGB.
    //
    // vim's rules [See check_termcode() in vim's term.c.]:
    // 1;95;0        -> underline_rgb, mouse_sgr
    // 0;95;0        ->                mouse_sgr
    // 83;>=40700+;* ->                mouse_sgr
    // 83;<40700;*   ->                mouse_xterm
    // *;>=277;*     ->                mouse_sgr
    // *;>=95;*      ->                mouse_xterm2
    // *;>=2500;*    -> underline_rgb
    // 0;136;0       -> underline_rgb, mouse_sgr
    // *;136;0       -> underline_rgb
    // 0;115;0       -> underline_rgb
    // 83;>=30600;*  ->                                 cursor_style=no, cursor_blink=no
    // *;<95;*       -> underline_rgb
    // *;<270;*      ->                                 cursor_style=no
    //
    // emacs's rules [see xterm.el]:
    // emu = first parameter in response
    // version = second parameter in response
    //   if version > 2000 && (emu == 1 || emu == 65):
    //     if version > 4000:
    //       send \e]11;?\e\ (queries background color), run xterm--report-background-handler on response
    //     version=200
    //   if emu == 83:
    //     version=200
    //   if version >= 242:
    //     Send \e]11;?\e\\ (queries background color), run xterm--report-background-handler on response
    //   if version >= 216:
    //     xterm--init-modify-other-keys  (enable mok 1)
    //   if version >= 203:
    //     xterm--init-activate-set-selection  (enable OSC 52, I think)
    //
    // neovim does not use DA2; it relies on $TERM and environment variables.
    NSString *report = [NSString stringWithFormat:@"\033[>%d;%d;0c", vt, xtermVersion];
    return [report dataUsingEncoding:NSISOLatin1StringEncoding];
}

- (NSData *)reportTertiaryDeviceAttribute {
    switch (_vtLevel) {
        case VT100EmulationLevel100:
        case VT100EmulationLevel200:
            return nil;
        case VT100EmulationLevel400:
            return [[NSString stringWithFormat:@"\eP!|%02X%02X%02X%02X\e\\", 'i', 'T', 'r', 'm'] dataUsingEncoding:NSUTF8StringEncoding];
    }
    return nil;
}

- (NSData *)reportExtendedDeviceAttribute {
    NSString *versionString = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSString *reportString = [NSString stringWithFormat:@"%cP>|iTerm2 %@%c\\", ESC, versionString, ESC];
    return [reportString dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportColor:(NSColor *)color atIndex:(int)index prefix:(NSString *)prefix {
    NSString *string = nil;
    if ([iTermAdvancedSettingsModel oscColorReport16Bits]) {
        string = [NSString stringWithFormat:@"%c]%@%d;rgb:%04x/%04x/%04x%c\\",
                  ESC,
                  prefix,
                  index,
                  (int) ([color redComponent] * 65535.0),
                  (int) ([color greenComponent] * 65535.0),
                  (int) ([color blueComponent] * 65535.0),
                  ESC];
    } else {
        string = [NSString stringWithFormat:@"%c]%@%d;rgb:%02x/%02x/%02x%c\\",
                  ESC,
                  prefix,
                  index,
                  (int) ([color redComponent] * 255.0),
                  (int) ([color greenComponent] * 255.0),
                  (int) ([color blueComponent] * 255.0),
                  ESC];
    }
    return [string dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportChecksum:(int)checksum withIdentifier:(int)identifier {
    // DCS Pid ! ~ D..D ST
    NSString *string =
        [NSString stringWithFormat:@"%cP%d!~%04x%c\\", ESC, identifier, (short)checksum, ESC];
    return [string dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportSGRCodes:(NSArray<NSString *> *)codes {
    NSString *string = [NSString stringWithFormat:@"%c[%@m", ESC, [codes componentsJoinedByString:@";"]];
    return [string dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - Private

- (int)cursorModifierParamForEventModifierFlags:(NSEventModifierFlags)modflag {
    // Normal mode
    static int metaModifierValues[] = {
        0,  // Nothing
        2,  // Shift
        5,  // Control
        6,  // Control Shift
        9,  // Meta
        10, // Meta Shift
        13, // Meta Control
        14  // Meta Control Shift
    };
    static int altModifierValues[] = {
        0,  // Nothing
        2,  // Shift
        5,  // Control
        6,  // Control Shift
        3,  // Alt
        4,  // Alt Shift
        7,  // Alt Control
        8   // Alt Control Shift
    };


    int theIndex = 0;
    if (modflag & NSEventModifierFlagOption) {
        theIndex |= 4;
    }
    if (modflag & NSEventModifierFlagControl) {
        theIndex |= 2;
    }
    if (modflag & NSEventModifierFlagShift) {
        theIndex |= 1;
    }
    int *modValues = _optionIsMetaForSpecialKeys ? metaModifierValues : altModifierValues;
    return modValues[theIndex];
}

- (NSData *)specialKey:(int)terminfo
             cursorMod:(char *)cursorMod
             cursorSet:(char *)cursorSet
           cursorReset:(char *)cursorReset
               modflag:(unsigned int)modflag
              isCursor:(BOOL)isCursor {
    NSData* prefix = nil;
    NSData* theSuffix;
    const int mod = [self cursorModifierParamForEventModifierFlags:modflag];
    if (_keyStrings[terminfo] && mod == 0 && !isCursor && self.keypadMode) {
        // Application keypad mode.
        theSuffix = [NSData dataWithBytes:_keyStrings[terminfo]
                                   length:strlen(_keyStrings[terminfo])];
    } else {
        if (mod) {
            NSString *format = [NSString stringWithCString:cursorMod encoding:NSUTF8StringEncoding];
            NSString *string = [format stringByReplacingOccurrencesOfString:@"%d"
                                                                 withString:[@(mod) stringValue]];
            theSuffix = [string dataUsingEncoding:NSISOLatin1StringEncoding];
        } else {
            if (self.cursorMode) {
                theSuffix = [NSData dataWithBytes:cursorSet
                                           length:strlen(cursorSet)];
            } else {
                theSuffix = [NSData dataWithBytes:cursorReset
                                           length:strlen(cursorReset)];
            }
        }
    }
    NSMutableData* data = [NSMutableData data];
    if (prefix) {
        [data appendData:prefix];
    }
    [data appendData:theSuffix];
    return data;
}

- (NSData *)reportFocusGained:(BOOL)gained {
    char flag = gained ? 'I' : 'O';
    NSString *message = [NSString stringWithFormat:@"%c[%c", 27, flag];
    return [message dataUsingEncoding:NSUTF8StringEncoding];
}


- (NSData *)reportCursorInformation:(VT100OutputCursorInformation)info {
    return [[NSString stringWithFormat:@"\eP1$u%d;%d;%d;%c;%c;%c;%d;%d;%c;%s%s%s%s\e\\",
             info.pr,
             info.pc,
             info.pp,
             info.srend,
             info.satt,
             info.sflag,
             info.pgl,
             info.pgr,
             info.scss,
             info.sdesig[0],
             info.sdesig[1],
             info.sdesig[2],
             info.sdesig[3]] dataUsingEncoding:NSUTF8StringEncoding];
}

VT100OutputCursorInformation VT100OutputCursorInformationCreate(int row,  // 1-based
                                                                int column,  // 1-based
                                                                BOOL reverseVideo,
                                                                BOOL blink,
                                                                BOOL underline,
                                                                BOOL bold,
                                                                BOOL autowrapPending,
                                                                BOOL lineDrawingMode,  // ss2: g2 mapped into gl
                                                                BOOL originMode) {
    return (VT100OutputCursorInformation){
        .pr = row,
        .pc = column,
        .pp = 1,  // Pages are not supported so it's always page 1.
        .srend = 0x40 | (reverseVideo ? 8 : 0) | (blink ? 4 : 0) | (underline ? 2 : 0) | (bold ? 1 : 0),
        .satt = 0x40,  // selective erase not supported yet.
        .sflag = 0x40 | (autowrapPending ? 8 : 0) | (originMode ? 1 : 0),
        .pgl = 0,  // g0 in gl
        .pgr = 2,  // g0 in gr
        .scss = 0x4f,  // g0, g1, g2, g3 set sizes are all 96 chars. No extension.
        .sdesig = { (lineDrawingMode ? "0" : "B"), "B", "B", "B" }  // B=G0, 0=G1
    };
}

VT100OutputCursorInformation VT100OutputCursorInformationFromString(NSString *string, BOOL *ok) {
    NSArray<NSString *> *parts = [string componentsSeparatedByString:@";"];
    if (parts.count < 10 ||
        [parts[3] length] < 1 ||
        [parts[4] length] < 1 ||
        [parts[5] length] < 1 ||
        [parts[6] length] < 1) {
        *ok = NO;
        return (VT100OutputCursorInformation) { 0 };
    }
    const char srend = [parts[3] characterAtIndex:0];
    const char satt = [parts[4] characterAtIndex:0];
    const char sflag = [parts[5] characterAtIndex:0];
    const char scss = [parts[6] characterAtIndex:0];
    char const *sdesig[4];
    NSString *s = parts[9];

    NSString *(^consume)(int, NSString *, char const **) = ^NSString *(int i, NSString *input, char const **output) {
        static const char *values[] = { "B", "0", "%5" };
        for (int j = 0; j < sizeof(values) / sizeof(*values); j++) {
            NSString *value = [NSString stringWithUTF8String:values[j]];
            if ([input hasPrefix:value]) {
                output[i] = values[j];
                return [input substringFromIndex:value.length];
            }
        }
        return nil;
    };
    for (int i = 0; i < 4; i++) {
        s = consume(i, s, sdesig);
        if (!s) {
            *ok = NO;
            return (VT100OutputCursorInformation) { 0 };
        }
    }
    *ok = YES;
    return (VT100OutputCursorInformation){
        .pr = [parts[0] intValue],
        .pc = [parts[1] intValue],
        .pp = [parts[2] intValue],
        .srend = srend,
        .satt = satt,
        .sflag = sflag,
        .pgl = [parts[6] intValue],
        .pgr = [parts[7] intValue],
        .scss = scss,
        .sdesig = { sdesig[0], sdesig[1], sdesig[2], sdesig[3] }
    };
}

int VT100OutputCursorInformationGetCursorX(VT100OutputCursorInformation info) {
    return info.pc;
}

int VT100OutputCursorInformationGetCursorY(VT100OutputCursorInformation info) {
    return info.pr;
}

BOOL VT100OutputCursorInformationGetReverseVideo(VT100OutputCursorInformation info) {
    return !!(info.srend & 8);
}

BOOL VT100OutputCursorInformationGetBlink(VT100OutputCursorInformation info) {
    return !!(info.srend & 4);
}

BOOL VT100OutputCursorInformationGetUnderline(VT100OutputCursorInformation info) {
    return !!(info.srend & 2);
}

BOOL VT100OutputCursorInformationGetBold(VT100OutputCursorInformation info) {
    return !!(info.srend & 1);
}

BOOL VT100OutputCursorInformationGetAutowrapPending(VT100OutputCursorInformation info) {
    return !!(info.sflag & 8);
}

BOOL VT100OutputCursorInformationGetOriginMode(VT100OutputCursorInformation info) {
    return !!(info.sflag & 1);
}

BOOL VT100OutputCursorInformationGetLineDrawingMode(VT100OutputCursorInformation info) {
    return !strcmp("0", info.sdesig[0]);
}

- (NSData *)reportTabStops:(NSArray<NSNumber *> *)tabStops {
    NSString *stops = [[tabStops mapWithBlock:^id(NSNumber *anObject) {
        return [anObject stringValue];
    }] componentsJoinedByString:@"/"];
    return [[NSString stringWithFormat:@"\eP2$u%@\e\\", stops] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportSavedColorsUsed:(int)used
                      largestUsed:(int)last {
    return [[NSString stringWithFormat:@"\e[?%d;%d#Q", used, last] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportGraphicsAttributeWithItem:(int)item status:(int)status value:(NSString *)value {
    return [[NSString stringWithFormat:@"\e[?%d;%d;%@S", item, status, value] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportDECDSR:(int)code {
    return [[NSString stringWithFormat:@"\e[?%dn", code] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportDECDSR:(int)code :(int)subcode {
    return [[NSString stringWithFormat:@"\e[?%d;%dn", code, subcode] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportMacroSpace:(int)space {
    return [[NSString stringWithFormat:@"\e[%04X*{", space] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportMemoryChecksum:(int)checksum id:(int)reqid {
    return [[NSString stringWithFormat:@"\eP%d!~%04X\e\\",
             MAX(1, reqid), checksum] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportVariableNamed:(NSString *)name value:(NSString *)variableValue {
    NSString *encodedValue = @"";
    if (variableValue) {
        encodedValue = [[variableValue dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    }
    NSString *report = [NSString stringWithFormat:@"\e]1337;ReportVariable=%@\a",
                        encodedValue ?: @""];
    return [report dataUsingEncoding:NSUTF8StringEncoding];
}

VT100Capabilities VT100OutputMakeCapabilities(BOOL compatibility24Bit,
                                              BOOL full24Bit,
                                              BOOL clipboardWritable,
                                              BOOL decslrm,
                                              BOOL mouse,
                                              BOOL DECSCUSR14,
                                              BOOL DECSCUSR56,
                                              BOOL DECSCUSR0,
                                              BOOL unicode,
                                              BOOL ambiguousWide,
                                              uint32_t unicodeVersion,
                                              BOOL titleStacks,
                                              BOOL titleSetting,
                                              BOOL bracketedPaste,
                                              BOOL focusReporting,
                                              BOOL strikethrough,
                                              BOOL overline,
                                              BOOL sync,
                                              BOOL hyperlinks,
                                              BOOL notifications,
                                              BOOL sixel,
                                              BOOL file) {
    const VT100Capabilities capabilities = {
        .twentyFourBit = (compatibility24Bit ? 1 : 0) | (full24Bit ? 2 : 0),
        .clipboardWritable = clipboardWritable,
        .DECSLRM = decslrm,
        .mouse = mouse,
        .DECSCUSR = (DECSCUSR14 ? 1 : 0) | (DECSCUSR56 ? 2 : 0) | (DECSCUSR0 ? 4 : 0),
        .unicodeBasic = unicode,
        .ambiguousWide = ambiguousWide,
        .unicodeWidths = unicodeVersion,
        .titles = (titleStacks ? 1 : 0) | (titleSetting ? 2 : 0),
        .bracketedPaste = bracketedPaste,
        .focusReporting = focusReporting,
        .strikethrough = strikethrough,
        .overline = overline,
        .sync = sync,
        .hyperlinks = hyperlinks,
        .notifications = notifications,
        .sixel = sixel,
        .file = file,
    };
    return capabilities;
}

- (NSData *)reportCapabilities:(VT100Capabilities)capabilities {
    NSString *(^formatNumber)(NSString *, uint32_t) = ^NSString *(NSString *code, uint32_t value) {
        if (value == 0) {
            return @"";
        }
        return [NSString stringWithFormat:@"%@%@", code, @(value)];
    };
    NSArray<NSString *> *parts = @[
        formatNumber(@"T", capabilities.twentyFourBit),
        capabilities.clipboardWritable ? @"Cw" : @"",
        capabilities.DECSLRM ? @"Lr" : @"",
        capabilities.mouse ? @"M" : @"",
        formatNumber(@"Sc", capabilities.DECSCUSR),
        capabilities.unicodeBasic ? @"U" : @"",
        capabilities.ambiguousWide ? @"Aw" : @"",
        formatNumber(@"Uw", capabilities.unicodeWidths),
        formatNumber(@"Ts", capabilities.titles),
        capabilities.bracketedPaste ? @"B" : @"",
        capabilities.focusReporting ? @"F" : @"",
        capabilities.strikethrough ? @"Gs" : @"",
        capabilities.overline ? @"Go" : @"",
        capabilities.sync ? @"Sy" : @"",
        capabilities.hyperlinks ? @"H" : @"",
        capabilities.notifications ? @"No" : @"",
        capabilities.sixel ? @"Sx" : @"",
        capabilities.file ? @"F" : @"",
    ];
    NSString *encodedValue = [parts componentsJoinedByString:@""];
    NSString *report = [NSString stringWithFormat:@"\e]1337;Capabilities=%@\a",
                        encodedValue ?: @""];
    return [report dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportPasteboard:(NSString *)pasteboard contents:(NSString *)string {
    NSString *report = [NSString stringWithFormat:@"\e]52;%@;%@\e\\",
                        pasteboard, [string base64EncodedWithEncoding:NSUTF8StringEncoding]];
    return [report dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    return [[VT100Output alloc] initWithOutput:self];
}

- (VT100Output *)copy {
    return [self copyWithZone:nil];
}

@end
