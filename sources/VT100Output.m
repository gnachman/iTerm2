#import "VT100Output.h"
#include <term.h>

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
    
    // for SGR 1006 style, internal use only
    MOUSE_BUTTON_SGR_RELEASE_FLAG = 128  // mouse button was released
    
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

#define ALT_KP_0        "\033Op"
#define ALT_KP_1        "\033Oq"
#define ALT_KP_2        "\033Or"
#define ALT_KP_3        "\033Os"
#define ALT_KP_4        "\033Ot"
#define ALT_KP_5        "\033Ou"
#define ALT_KP_6        "\033Ov"
#define ALT_KP_7        "\033Ow"
#define ALT_KP_8        "\033Ox"
#define ALT_KP_9        "\033Oy"
#define ALT_KP_MINUS    "\033Om"
#define ALT_KP_PLUS     "\033Ok"
#define ALT_KP_PERIOD   "\033On"
#define ALT_KP_SLASH    "\033Oo"
#define ALT_KP_STAR     "\033Oj"
#define ALT_KP_EQUALS   "\033OX"
#define ALT_KP_ENTER    "\033OM"

// Reporting formats
#define KEY_FUNCTION_FORMAT  "\033[%d~"

#define REPORT_POSITION      "\033[%d;%dR"
#define REPORT_POSITION_Q    "\033[?%d;%dR"
#define REPORT_STATUS        "\033[0n"
// Device Attribute : VT100 with Advanced Video Option
#define REPORT_WHATAREYOU    "\033[?1;2c"
// Secondary Device Attribute: VT100

// TODO: When xterm compatibility is reached, change 95 to 314 or later. Even 277 would be an
// improvement as it would let vim use ttym=sgr rather than xterm2, which passes through luit.
// However, it must return three arguments (at the very least) to keep vim happy. For more, see
// check_termcode() in vim's term.c.
#define REPORT_SDA           "\033[>0;95;0c"

#define REPORT_VT52          "\033/Z"

#define STATIC_STRLEN(n)   ((sizeof(n)) - 1)

@implementation VT100Output {
    // Indexed by values in VT100TerminalTerminfoKeys.
    // Gives strings to send for various special keys.
    char *_keyStrings[TERMINFO_KEYS];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.termTypeIsValid = YES;
        _optionIsMetaForSpecialKeys = YES;
    }
    return self;
}

- (void)dealloc {
    for (int i = 0; i < TERMINFO_KEYS; i ++) {
        if (_keyStrings[i]) {
            free(_keyStrings[i]);
        }
    }
    [super dealloc];
}

- (void)setTermTypeIsValid:(BOOL)termTypeIsValid {
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

- (NSData *)keyArrowUp:(unsigned int)modflag
{
    return [self specialKey:TERMINFO_KEY_UP
                  cursorMod:CURSOR_MOD_UP
                  cursorSet:CURSOR_SET_UP
                cursorReset:CURSOR_RESET_UP
                    modflag:modflag];
}

- (NSData *)keyArrowDown:(unsigned int)modflag
{
    return [self specialKey:TERMINFO_KEY_DOWN
                  cursorMod:CURSOR_MOD_DOWN
                  cursorSet:CURSOR_SET_DOWN
                cursorReset:CURSOR_RESET_DOWN
                    modflag:modflag];
}

- (NSData *)keyArrowLeft:(unsigned int)modflag
{
    return [self specialKey:TERMINFO_KEY_LEFT
                  cursorMod:CURSOR_MOD_LEFT
                  cursorSet:CURSOR_SET_LEFT
                cursorReset:CURSOR_RESET_LEFT
                    modflag:modflag];
}

- (NSData *)keyArrowRight:(unsigned int)modflag
{
    return [self specialKey:TERMINFO_KEY_RIGHT
                  cursorMod:CURSOR_MOD_RIGHT
                  cursorSet:CURSOR_SET_RIGHT
                cursorReset:CURSOR_RESET_RIGHT
                    modflag:modflag];
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
                    modflag:modflag];
}

- (NSData *)keyEnd:(unsigned int)modflag screenlikeTerminal:(BOOL)screenlike
{
    if (screenlike) {
        const char *bytes = "\033[4~";
        return [NSData dataWithBytes:bytes length:strlen(bytes)];
    }
    return [self specialKey:TERMINFO_KEY_END
                  cursorMod:CURSOR_MOD_END
                  cursorSet:CURSOR_SET_END
                cursorReset:CURSOR_RESET_END
                    modflag:modflag];
}

- (NSData *)keyInsert
{
    if (_keyStrings[TERMINFO_KEY_INS]) {
        return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_INS]
                              length:strlen(_keyStrings[TERMINFO_KEY_INS])];
    } else {
        return [NSData dataWithBytes:KEY_INSERT length:STATIC_STRLEN(KEY_INSERT)];
    }
}


- (NSData *)keyDelete
{
    if (_keyStrings[TERMINFO_KEY_DEL]) {
        return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_DEL]
                              length:strlen(_keyStrings[TERMINFO_KEY_DEL])];
    } else {
        return [NSData dataWithBytes:KEY_DEL length:STATIC_STRLEN(KEY_DEL)];
    }
}

- (NSData *)keyBackspace
{
    if (_keyStrings[TERMINFO_KEY_BACKSPACE]) {
        return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_BACKSPACE]
                              length:strlen(_keyStrings[TERMINFO_KEY_BACKSPACE])];
    } else {
        return [NSData dataWithBytes:KEY_BACKSPACE length:STATIC_STRLEN(KEY_BACKSPACE)];
    }
}

- (NSData *)keyPageUp:(unsigned int)modflag
{
    NSData* theSuffix;
    if (_keyStrings[TERMINFO_KEY_PAGEUP]) {
        theSuffix = [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_PAGEUP]
                                   length:strlen(_keyStrings[TERMINFO_KEY_PAGEUP])];
    } else {
        theSuffix = [NSData dataWithBytes:KEY_PAGE_UP
                                   length:STATIC_STRLEN(KEY_PAGE_UP)];
    }
    NSMutableData* data = [[[NSMutableData alloc] init] autorelease];
    if (modflag & NSAlternateKeyMask) {
        char esc = ESC;
        [data appendData:[NSData dataWithBytes:&esc length:1]];
    }
    [data appendData:theSuffix];
    return data;
}

- (NSData *)keyPageDown:(unsigned int)modflag
{
    NSData* theSuffix;
    if (_keyStrings[TERMINFO_KEY_PAGEDOWN]) {
        theSuffix = [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_PAGEDOWN]
                                   length:strlen(_keyStrings[TERMINFO_KEY_PAGEDOWN])];
    } else {
        theSuffix = [NSData dataWithBytes:KEY_PAGE_DOWN
                                   length:STATIC_STRLEN(KEY_PAGE_DOWN)];
    }
    NSMutableData* data = [[[NSMutableData alloc] init] autorelease];
    if (modflag & NSAlternateKeyMask) {
        char esc = ESC;
        [data appendData:[NSData dataWithBytes:&esc length:1]];
    }
    [data appendData:theSuffix];
    return data;
}

// Reference: http://www.utexas.edu/cc/faqs/unix/VT200-function-keys.html
// http://www.cs.utk.edu/~shuford/terminal/misc_old_terminals_news.txt
- (NSData *)keyFunction:(int)no
{
    char str[256];
    int len;
    
    if (no <= 5) {
        if (_keyStrings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_F0+no]
                                  length:strlen(_keyStrings[TERMINFO_KEY_F0+no])];
        }
        else {
            sprintf(str, KEY_FUNCTION_FORMAT, no + 10);
        }
    }
    else if (no <= 10) {
        if (_keyStrings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_F0+no]
                                  length:strlen(_keyStrings[TERMINFO_KEY_F0+no])];
        }
        else {
            sprintf(str, KEY_FUNCTION_FORMAT, no + 11);
        }
    }
    else if (no <= 14)
        if (_keyStrings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_F0+no]
                                  length:strlen(_keyStrings[TERMINFO_KEY_F0+no])];
        }
        else {
            sprintf(str, KEY_FUNCTION_FORMAT, no + 12);
        }
        else if (no <= 16)
            if (_keyStrings[TERMINFO_KEY_F0+no]) {
                return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_F0+no]
                                      length:strlen(_keyStrings[TERMINFO_KEY_F0+no])];
            }
            else {
                sprintf(str, KEY_FUNCTION_FORMAT, no + 13);
            }
            else if (no <= 20)
                if (_keyStrings[TERMINFO_KEY_F0+no]) {
                    return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_F0+no]
                                          length:strlen(_keyStrings[TERMINFO_KEY_F0+no])];
                }
                else {
                    sprintf(str, KEY_FUNCTION_FORMAT, no + 14);
                }
                else if (no <=35)
                    if (_keyStrings[TERMINFO_KEY_F0+no]) {
                        return [NSData dataWithBytes:_keyStrings[TERMINFO_KEY_F0+no]
                                              length:strlen(_keyStrings[TERMINFO_KEY_F0+no])];
                    }
                    else
                        str[0] = 0;
                    else
                        str[0] = 0;
    
    len = strlen(str);
    return [NSData dataWithBytes:str length:len];
}

- (NSData*)keypadData:(unichar)unicode keystr:(NSString*)keystr
{
    NSData *theData = nil;
    
    // numeric keypad mode
    if (!self.keypadMode) {
        return ([keystr dataUsingEncoding:NSUTF8StringEncoding]);
    }
    // alternate keypad mode
    switch (unicode) {
        case '0':
            theData = [NSData dataWithBytes:ALT_KP_0 length:STATIC_STRLEN(ALT_KP_0)];
            break;
        case '1':
            theData = [NSData dataWithBytes:ALT_KP_1 length:STATIC_STRLEN(ALT_KP_1)];
            break;
        case '2':
            theData = [NSData dataWithBytes:ALT_KP_2 length:STATIC_STRLEN(ALT_KP_2)];
            break;
        case '3':
            theData = [NSData dataWithBytes:ALT_KP_3 length:STATIC_STRLEN(ALT_KP_3)];
            break;
        case '4':
            theData = [NSData dataWithBytes:ALT_KP_4 length:STATIC_STRLEN(ALT_KP_4)];
            break;
        case '5':
            theData = [NSData dataWithBytes:ALT_KP_5 length:STATIC_STRLEN(ALT_KP_5)];
            break;
        case '6':
            theData = [NSData dataWithBytes:ALT_KP_6 length:STATIC_STRLEN(ALT_KP_6)];
            break;
        case '7':
            theData = [NSData dataWithBytes:ALT_KP_7 length:STATIC_STRLEN(ALT_KP_7)];
            break;
        case '8':
            theData = [NSData dataWithBytes:ALT_KP_8 length:STATIC_STRLEN(ALT_KP_8)];
            break;
        case '9':
            theData = [NSData dataWithBytes:ALT_KP_9 length:STATIC_STRLEN(ALT_KP_9)];
            break;
        case '-':
            theData = [NSData dataWithBytes:ALT_KP_MINUS length:STATIC_STRLEN(ALT_KP_MINUS)];
            break;
        case '+':
            theData = [NSData dataWithBytes:ALT_KP_PLUS length:STATIC_STRLEN(ALT_KP_PLUS)];
            break;
        case '.':
            theData = [NSData dataWithBytes:ALT_KP_PERIOD length:STATIC_STRLEN(ALT_KP_PERIOD)];
            break;
        case '/':
            theData = [NSData dataWithBytes:ALT_KP_SLASH length:STATIC_STRLEN(ALT_KP_SLASH)];
            break;
        case '*':
            theData = [NSData dataWithBytes:ALT_KP_STAR length:STATIC_STRLEN(ALT_KP_STAR)];
            break;
        case '=':
            theData = [NSData dataWithBytes:ALT_KP_EQUALS length:STATIC_STRLEN(ALT_KP_EQUALS)];
            break;
        case 0x03:
            theData = [NSData dataWithBytes:ALT_KP_ENTER length:STATIC_STRLEN(ALT_KP_ENTER)];
            break;
        default:
            theData = [keystr dataUsingEncoding:NSUTF8StringEncoding];
            break;
    }
    
    return (theData);
}

- (char *)mouseReport:(int)button atX:(int)x Y:(int)y
{
    static char buf[64]; // This should be enough for all formats.
    switch (self.mouseFormat) {
        case MOUSE_FORMAT_XTERM_EXT:
            // TODO: This doesn' thandle positions greater than 223 correctly. It should use UTF-8.
            snprintf(buf, sizeof(buf), "\033[M%c%lc%lc",
                     (wint_t) (32 + button),
                     (wint_t) (32 + x),
                     (wint_t) (32 + y));
            break;
        case MOUSE_FORMAT_URXVT:
            snprintf(buf, sizeof(buf), "\033[%d;%d;%dM", 32 + button, x, y);
            break;
        case MOUSE_FORMAT_SGR:
            if (button & MOUSE_BUTTON_SGR_RELEASE_FLAG) {
                // for mouse release event
                snprintf(buf, sizeof(buf), "\033[<%d;%d;%dm",
                         button ^ MOUSE_BUTTON_SGR_RELEASE_FLAG,
                         x,
                         y);
            } else {
                // for mouse press/motion event
                snprintf(buf, sizeof(buf), "\033[<%d;%d;%dM", button, x, y);
            }
            break;
        case MOUSE_FORMAT_XTERM:
        default:
            snprintf(buf, sizeof(buf), "\033[M%c%c%c", 32 + button, 32 + x, 32 + y);
            break;
    }
    return buf;
}

- (NSData *)mousePress:(int)button withModifiers:(unsigned int)modflag at:(VT100GridCoord)coord {
    int cb;
    
    cb = button;
    if (button == MOUSE_BUTTON_SCROLLDOWN || button == MOUSE_BUTTON_SCROLLUP) {
        // convert x11 scroll button number to terminal button code
        const int offset = MOUSE_BUTTON_SCROLLDOWN;
        cb -= offset;
        cb |= MOUSE_BUTTON_SCROLL_FLAG;
    }
    if (modflag & NSControlKeyMask) {
        cb |= MOUSE_BUTTON_CTRL_FLAG;
    }
    if (modflag & NSShiftKeyMask) {
        cb |= MOUSE_BUTTON_SHIFT_FLAG;
    }
    if (modflag & NSCommandKeyMask) {
        cb |= MOUSE_BUTTON_META_FLAG;
    }
    char *buf = [self mouseReport:cb atX:(coord.x + 1) Y:(coord.y + 1)];
    
    return [NSData dataWithBytes: buf length: strlen(buf)];
}

- (NSData *)mouseRelease:(int)button withModifiers:(unsigned int)modflag at:(VT100GridCoord)coord {
    int cb;
    
    if (self.mouseFormat == MOUSE_FORMAT_SGR) {
        // for SGR 1006 mode
        cb = button | MOUSE_BUTTON_SGR_RELEASE_FLAG;
    } else {
        // for 1000/1005/1015 mode
        // To quote the xterm docs:
        // The low two bits of C b encode button information:
        // 0=MB1 pressed, 1=MB2 pressed, 2=MB3 pressed, 3=release.
        cb = 3;
    }
    
    if (modflag & NSControlKeyMask) {
        cb |= MOUSE_BUTTON_CTRL_FLAG;
    }
    if (modflag & NSShiftKeyMask) {
        cb |= MOUSE_BUTTON_SHIFT_FLAG;
    }
    if (modflag & NSCommandKeyMask) {
        cb |= MOUSE_BUTTON_META_FLAG;
    }
    char *buf = [self mouseReport:cb atX:(coord.x + 1) Y:(coord.y + 1)];
    
    return [NSData dataWithBytes: buf length: strlen(buf)];
}

- (NSData *)mouseMotion:(int)button withModifiers:(unsigned int)modflag at:(VT100GridCoord)coord {
    int cb;
    
    if (button == MOUSE_BUTTON_NONE) {
        cb = button;
    } else {
        cb = button % 3;
    }
    if (button > 3) {
        cb |= MOUSE_BUTTON_SCROLL_FLAG;
    }
    if (modflag & NSControlKeyMask) {
        cb |= MOUSE_BUTTON_CTRL_FLAG;
    }
    if (modflag & NSShiftKeyMask) {
        cb |= MOUSE_BUTTON_SHIFT_FLAG;
    }
    if (modflag & NSCommandKeyMask) {
        cb |= MOUSE_BUTTON_META_FLAG;
    }
    char *buf = [self mouseReport:(32 + cb) atX:(coord.x + 1) Y:(coord.y + 1)];
    
    return [NSData dataWithBytes: buf length: strlen(buf)];
}

- (NSData *)reportiTerm2Version {
    // We uppercase the string to ensure it does not contain a "n".
    // The [ must never be followed by a 0 (see the isiterm2.sh script for justification).
    NSString *version = [NSString stringWithFormat:@"%c[ITERM2 %@n", ESC,
                         [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] uppercaseString]];
    return [version dataUsingEncoding:NSUTF8StringEncoding];
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

- (NSData *)reportDeviceAttribute
{
    return [NSData dataWithBytes:REPORT_WHATAREYOU
                          length:STATIC_STRLEN(REPORT_WHATAREYOU)];
}

- (NSData *)reportSecondaryDeviceAttribute
{
    return [NSData dataWithBytes:REPORT_SDA
                          length:STATIC_STRLEN(REPORT_SDA)];
}

- (NSData *)reportColor:(NSColor *)color atIndex:(int)index {
    NSString *string = [NSString stringWithFormat:@"%c]4;%d;rgb:%02x/%02x/%02x%c",
                           ESC, index,
                           (int) ([color redComponent] * 255.0),
                           (int) ([color greenComponent] * 255.0),
                           (int) ([color blueComponent] * 255.0),
                           7];
    return [string dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)reportChecksum:(int)checksum withIdentifier:(int)identifier {
    // DCS Pid ! ~ D..D ST
    NSString *string =
        [NSString stringWithFormat:@"%cP%d!~%04x%c\\", ESC, identifier, (short)checksum, ESC];
    return [string dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - Private

- (NSData *)specialKey:(int)terminfo
             cursorMod:(char*)cursorMod
             cursorSet:(char*)cursorSet
           cursorReset:(char*)cursorReset
               modflag:(unsigned int)modflag {
    NSData* prefix = nil;
    NSData* theSuffix;
    if (_keyStrings[terminfo] && self.keypadMode) {
        // Application keypad mode
        theSuffix = [NSData dataWithBytes:_keyStrings[terminfo]
                                   length:strlen(_keyStrings[terminfo])];
    } else {
        // Normal mode
        int mod = 0;
        static char buf[20];
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
        if (modflag & NSAlternateKeyMask) {
            theIndex |= 4;
        }
        if (modflag & NSControlKeyMask) {
            theIndex |= 2;
        }
        if (modflag & NSShiftKeyMask) {
            theIndex |= 1;
        }
        int *modValues = _optionIsMetaForSpecialKeys ? metaModifierValues : altModifierValues;
        mod = modValues[theIndex];
        
        if (mod) {
            sprintf(buf, cursorMod, mod);
            theSuffix = [NSData dataWithBytes:buf length:strlen(buf)];
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
    NSMutableData* data = [[[NSMutableData alloc] init] autorelease];
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


@end
