//
//  VT100Token.m
//  iTerm
//
//  Created by George Nachman on 3/3/14.
//
//

#import "VT100Token.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermMalloc.h"

#include <stdlib.h>
@interface VT100Token ()
@property(nonatomic, readwrite) CSIParam *csi;
@end

@implementation VT100Token {
    AsciiData _asciiData;
    ScreenChars _screenChars;
}

+ (instancetype)token {
    return [[[VT100Token alloc] init] autorelease];
}

+ (instancetype)newTokenForControlCharacter:(unsigned char)controlCharacter {
    VT100Token *token = [[VT100Token alloc] init];
    token->type = controlCharacter;
    return token;
}

void iTermAsciiDataFree(AsciiData *asciiData) {
    if (asciiData->buffer != asciiData->staticBuffer) {
        free(asciiData->buffer);
    }
    if (asciiData->screenChars &&
        asciiData->screenChars->buffer != asciiData->screenChars->staticBuffer) {
        free(asciiData->screenChars->buffer);
    }
}

void iTermAsciiDataSet(AsciiData *asciiData, const char *bytes, int length, ScreenChars *screenChars) {
    assert(asciiData->buffer == NULL);

    asciiData->length = length;
    if (length > sizeof(asciiData->staticBuffer)) {
        asciiData->buffer = iTermMalloc(length);
    } else {
        asciiData->buffer = asciiData->staticBuffer;
    }
    memcpy(asciiData->buffer, bytes, length);

    if (asciiData->length > kStaticScreenCharsCount) {
        screenChars->buffer = iTermCalloc(asciiData->length, sizeof(screen_char_t));
    } else {
        screenChars->buffer = screenChars->staticBuffer;
        memset(screenChars->buffer, 0, asciiData->length * sizeof(screen_char_t));
    }
    for (NSInteger i = 0; i < length; i++) {
        screenChars->buffer[i].code = asciiData->buffer[i];
    }
    screenChars->length = asciiData->length;
    asciiData->screenChars = screenChars;
}


- (void)dealloc {
    if (_csi) {
        free(_csi);
    }

    [_string release];
    [_kvpKey release];
    [_kvpValue release];
    [_savedData release];

    iTermAsciiDataFree(&_asciiData);

    [super dealloc];
}

- (NSString *)codeName {
    NSDictionary *map = @{@(VT100CC_NULL):                    @"VT100CC_NULL",
                          @(VT100CC_SOH):                     @"VT100CC_SOH",
                          @(VT100CC_STX):                     @"VT100CC_STX",
                          @(VT100CC_ETX):                     @"VT100CC_ETX",
                          @(VT100CC_EOT):                     @"VT100CC_EOT",
                          @(VT100CC_ENQ):                     @"VT100CC_ENQ",
                          @(VT100CC_ACK):                     @"VT100CC_ACK",
                          @(VT100CC_BEL):                     @"VT100CC_BEL",
                          @(VT100CC_BS):                      @"VT100CC_BS",
                          @(VT100CC_HT):                      @"VT100CC_HT",
                          @(VT100CC_LF):                      @"VT100CC_LF",
                          @(VT100CC_VT):                      @"VT100CC_VT",
                          @(VT100CC_FF):                      @"VT100CC_FF",
                          @(VT100CC_CR):                      @"VT100CC_CR",
                          @(VT100CC_SO):                      @"VT100CC_SO",
                          @(VT100CC_SI):                      @"VT100CC_SI",
                          @(VT100CC_DLE):                     @"VT100CC_DLE",
                          @(VT100CC_DC1):                     @"VT100CC_DC1",
                          @(VT100CC_DC2):                     @"VT100CC_DC2",
                          @(VT100CC_DC3):                     @"VT100CC_DC3",
                          @(VT100CC_DC4):                     @"VT100CC_DC4",
                          @(VT100CC_NAK):                     @"VT100CC_NAK",
                          @(VT100CC_SYN):                     @"VT100CC_SYN",
                          @(VT100CC_ETB):                     @"VT100CC_ETB",
                          @(VT100CC_CAN):                     @"VT100CC_CAN",
                          @(VT100CC_EM):                      @"VT100CC_EM",
                          @(VT100CC_SUB):                     @"VT100CC_SUB",
                          @(VT100CC_ESC):                     @"VT100CC_ESC",
                          @(VT100CC_FS):                      @"VT100CC_FS",
                          @(VT100CC_GS):                      @"VT100CC_GS",
                          @(VT100CC_RS):                      @"VT100CC_RS",
                          @(VT100CC_US):                      @"VT100CC_US",
                          @(VT100CC_DEL):                     @"VT100CC_DEL",
                          @(VT100_WAIT):                      @"VT100_WAIT",
                          @(VT100_NOTSUPPORT):                @"VT100_NOTSUPPORT",
                          @(VT100_SKIP):                      @"VT100_SKIP",
                          @(VT100_STRING):                    @"VT100_STRING",
                          @(VT100_ASCIISTRING):               @"VT100_ASCIISTRING",
                          @(VT100_UNKNOWNCHAR):               @"VT100_UNKNOWNCHAR",
                          @(VT100_INVALID_SEQUENCE):          @"VT100_INVALID_SEQUENCE",
                          @(VT100_BINARY_GARBAGE):            @"VT100_BINARY_GARBAGE",
                          @(VT100CSI_CPR):                    @"VT100CSI_CPR",
                          @(VT100CSI_CUB):                    @"VT100CSI_CUB",
                          @(VT100CSI_CUD):                    @"VT100CSI_CUD",
                          @(VT100CSI_CUF):                    @"VT100CSI_CUF",
                          @(VT100CSI_CUP):                    @"VT100CSI_CUP",
                          @(VT100CSI_CHT):                    @"VT100CSI_CHT",
                          @(VT100CSI_CUU):                    @"VT100CSI_CUU",
                          @(VT100CSI_DA):                     @"VT100CSI_DA",
                          @(VT100CSI_DA2):                    @"VT100CSI_DA2",
                          @(VT100CSI_DA3):                    @"VT100CSI_DA3",
                          @(VT100CSI_XDA):                    @"VT100CSI_XDA",
                          @(VT100CSI_DECALN):                 @"VT100CSI_DECALN",
                          @(VT100CSI_DECDHL):                 @"VT100CSI_DECDHL",
                          @(VT100CSI_DECDWL):                 @"VT100CSI_DECDWL",
                          @(VT100CSI_DECID):                  @"VT100CSI_DECID",
                          @(VT100CSI_DECKPAM):                @"VT100CSI_DECKPAM",
                          @(VT100CSI_DECKPNM):                @"VT100CSI_DECKPNM",
                          @(VT100CSI_DECRC):                  @"VT100CSI_DECRC",
                          @(VT100CSI_DECRQCRA):               @"VT100CSI_DECRQCRA",
                          @(VT100CSI_DECRST):                 @"VT100CSI_DECRST",
                          @(VT100CSI_DECSC):                  @"VT100CSI_DECSC",
                          @(VT100CSI_DECSET):                 @"VT100CSI_DECSET",
                          @(VT100CSI_DECSTBM):                @"VT100CSI_DECSTBM",
                          @(VT100CSI_DSR):                    @"VT100CSI_DSR",
                          @(VT100CSI_ED):                     @"VT100CSI_ED",
                          @(VT100CSI_EL):                     @"VT100CSI_EL",
                          @(VT100CSI_HTS):                    @"VT100CSI_HTS",
                          @(VT100CC_SPA):                     @"VT100CC_SPA",
                          @(VT100CC_EPA):                     @"VT100CC_EPA",
                          @(VT100CSI_HVP):                    @"VT100CSI_HVP",
                          @(VT100CSI_IND):                    @"VT100CSI_IND",
                          @(VT100CSI_NEL):                    @"VT100CSI_NEL",
                          @(VT100CSI_RI):                     @"VT100CSI_RI",
                          @(VT100CSI_RIS):                    @"VT100CSI_RIS",
                          @(VT100CSI_RM):                     @"VT100CSI_RM",
                          @(VT100CSI_SCS):                    @"VT100CSI_SCS",
                          @(VT100CSI_SCS0):                   @"VT100CSI_SCS0",
                          @(VT100CSI_SCS1):                   @"VT100CSI_SCS1",
                          @(VT100CSI_SCS2):                   @"VT100CSI_SCS2",
                          @(VT100CSI_SCS3):                   @"VT100CSI_SCS3",
                          @(VT100CSI_SGR):                    @"VT100CSI_SGR",
                          @(VT100CSI_DECCARA):                @"VT100CSI_DECCARA",
                          @(VT100CSI_DECRARA):                @"VT100CSI_DECRARA",
                          @(VT100CSI_DECSACE):                @"VT100CSI_DECSACE",
                          @(VT100CSI_DECCRA):                 @"VT100CSI_DECCRA",
                          @(VT100CSI_DECFRA):                 @"VT100CSI_DECFRA",
                          @(VT100CSI_DECERA):                 @"VT100CSI_DECERA",
                          @(VT100CSI_SM):                     @"VT100CSI_SM",
                          @(VT100CSI_TBC):                    @"VT100CSI_TBC",
                          @(VT100CSI_DECSCUSR):               @"VT100CSI_DECSCUSR",
                          @(VT100CSI_DECSTR):                 @"VT100CSI_DECSTR",
                          @(VT100CSI_DECDSR):                 @"VT100CSI_DECDSR",
                          @(VT100CSI_SET_MODIFIERS):          @"VT100CSI_SET_MODIFIERS",
                          @(VT100CSI_RESET_MODIFIERS):        @"VT100CSI_RESET_MODIFIERS",
                          @(VT100CSI_REP):                    @"VT100CSI_REP",
                          @(VT100CSI_XTREPORTSGR):            @"VT100CSI_XTREPORTSGR",
                          @(XTERMCC_XTPUSHCOLORS):            @"XTERMCC_XTPUSHCOLORS",
                          @(XTERMCC_XTPOPCOLORS):             @"XTERMCC_XTPOPCOLORS",
                          @(XTERMCC_XTREPORTCOLORS):          @"XTERMCC_XTREPORTCOLORS",
                          @(XTERMCC_XTSMGRAPHICS):            @"XTERMCC_XTSMGRAPHICS",
                          @(VT100CSI_DECSLRM):                @"VT100CSI_DECSLRM",
                          @(VT100CSI_DECRQM_DEC):             @"VT100CSI_DECRQM_DEC",
                          @(VT100CSI_DECRQM_ANSI):            @"VT100CSI_DECRQM_ANSI",
                          @(VT100CSI_DECRQPSR):               @"VT100CSI_DECRQPSR",
                          @(VT100CSI_SD):                     @"VT100CSI_SD",
                          @(VT100CSI_HPR):                    @"VT100CSI_HPR",
                          @(VT100CSI_DECSCPP):                @"VT100CSI_DECSCPP",
                          @(VT100CSI_DECSNLS):                @"VT100CSI_DECSNLS",
                          @(VT100CSI_DECIC):                  @"VT100CSI_DECIC",
                          @(VT100CSI_DECDC):                  @"VT100CSI_DECDC",
                          @(VT100CSI_DECSERA):                @"VT100CSI_DECSERA",
                          @(VT100CSI_DECSED):                 @"VT100CSI_DECSED",
                          @(VT100CSI_DECSEL):                 @"VT100CSI_DECSEL",
                          @(VT100CSI_DECSCA):                 @"VT100CSI_DECSCA",
                          @(VT100_DECFI):                     @"VT100_DECFI",
                          @(VT100_DECBI):                     @"VT100_DECBI",
                          @(VT100CSI_PUSH_KEY_REPORTING_MODE):@"VT100CSI_PUSH_KEY_REPORTING_MODE",
                          @(VT100CSI_POP_KEY_REPORTING_MODE): @"VT100CSI_POP_KEY_REPORTING_MODE",
                          @(VT100CSI_QUERY_KEY_REPORTING_MODE):@"VT100CSI_QUERY_KEY_REPORTING_MODE",
                          @(XTERMCC_WIN_TITLE):               @"XTERMCC_WIN_TITLE",
                          @(XTERMCC_ICON_TITLE):              @"XTERMCC_ICON_TITLE",
                          @(XTERMCC_WINICON_TITLE):           @"XTERMCC_WINICON_TITLE",
                          @(VT100CSI_ICH):                    @"VT100CSI_ICH",
                          @(VT100CSI_SL):                     @"VT100CSI_SL",
                          @(VT100CSI_SR):                     @"VT100CSI_SR",
                          @(XTERMCC_INSLN):                   @"XTERMCC_INSLN",
                          @(XTERMCC_DELCH):                   @"XTERMCC_DELCH",
                          @(XTERMCC_DELLN):                   @"XTERMCC_DELLN",
                          @(XTERMCC_WINDOWSIZE):              @"XTERMCC_WINDOWSIZE",
                          @(XTERMCC_WINDOWSIZE_PIXEL):        @"XTERMCC_WINDOWSIZE_PIXEL",
                          @(XTERMCC_WINDOWPOS):               @"XTERMCC_WINDOWPOS",
                          @(XTERMCC_ICONIFY):                 @"XTERMCC_ICONIFY",
                          @(XTERMCC_DEICONIFY):               @"XTERMCC_DEICONIFY",
                          @(XTERMCC_RAISE):                   @"XTERMCC_RAISE",
                          @(XTERMCC_LOWER):                   @"XTERMCC_LOWER",
                          @(XTERMCC_SU):                      @"XTERMCC_SU",
                          @(XTERMCC_SD):                      @"XTERMCC_SD",
                          @(XTERMCC_REPORT_WIN_STATE):        @"XTERMCC_REPORT_WIN_STATE",
                          @(XTERMCC_REPORT_WIN_POS):          @"XTERMCC_REPORT_WIN_POS",
                          @(XTERMCC_REPORT_WIN_PIX_SIZE):     @"XTERMCC_REPORT_WIN_PIX_SIZE",
                          @(XTERMCC_REPORT_WIN_SIZE):         @"XTERMCC_REPORT_WIN_SIZE",
                          @(XTERMCC_REPORT_SCREEN_SIZE):      @"XTERMCC_REPORT_SCREEN_SIZE",
                          @(XTERMCC_REPORT_ICON_TITLE):       @"XTERMCC_REPORT_ICON_TITLE",
                          @(XTERMCC_REPORT_WIN_TITLE):        @"XTERMCC_REPORT_WIN_TITLE",
                          @(XTERMCC_PUSH_TITLE):              @"XTERMCC_PUSH_TITLE",
                          @(XTERMCC_POP_TITLE):               @"XTERMCC_POP_TITLE",
                          @(VT100_DECSLPP):                   @"VT100_DECSLPP",
                          @(XTERMCC_SET_RGB):                 @"XTERMCC_SET_RGB",
                          @(XTERMCC_PROPRIETARY_ETERM_EXT):   @"XTERMCC_PROPRIETARY_ETERM_EXT",
                          @(XTERMCC_PWD_URL):                 @"XTERMCC_PWD_URL",
                          @(XTERMCC_SET_PALETTE):             @"XTERMCC_SET_PALETTE",
                          @(XTERMCC_SET_KVP):                 @"XTERMCC_SET_KVP",
                          @(XTERMCC_MULTITOKEN_HEADER_SET_KVP): @"XTERMCC_MULTITOKEN_HEADER_SET_KVP",
                          @(XTERMCC_MULTITOKEN_BODY):         @"XTERMCC_MULTITOKEN_BODY",
                          @(XTERMCC_MULTITOKEN_END):          @"XTERMCC_MULTITOKEN_END",
                          @(XTERMCC_PASTE64):                 @"XTERMCC_PASTE64",
                          @(XTERMCC_RESET_COLOR):             @"XTERMCC_RESET_COLOR",

                          @(XTERMCC_RESET_VT100_TEXT_FOREGROUND_COLOR): @"XTERMCC_RESET_VT100_TEXT_FOREGROUND_COLOR",
                          @(XTERMCC_RESET_VT100_TEXT_BACKGROUND_COLOR): @"XTERMCC_RESET_VT100_TEXT_BACKGROUND_COLOR",
                          @(XTERMCC_RESET_TEXT_CURSOR_COLOR):           @"XTERMCC_RESET_TEXT_CURSOR_COLOR",
                          @(XTERMCC_RESET_HIGHLIGHT_COLOR):             @"XTERMCC_RESET_HIGHLIGHT_COLOR",
                          @(XTERMCC_RESET_HIGHLIGHT_FOREGROUND_COLOR):  @"XTERMCC_RESET_HIGHLIGHT_FOREGROUND_COLOR",
                          
                          @(XTERMCC_SET_TEXT_CURSOR_COLOR):             @"XTERMCC_SET_TEXT_CURSOR_COLOR",
                          @(XTERMCC_SET_HIGHLIGHT_COLOR):               @"XTERMCC_SET_HIGHLIGHT_COLOR",
                          @(XTERMCC_SET_HIGHLIGHT_FOREGROUND_COLOR):    @"XTERMCC_SET_HIGHLIGHT_FOREGROUND_COLOR",

                          @(XTERMCC_FINAL_TERM):              @"XTERMCC_FINAL_TERM",
                          @(XTERMCC_FRAMER_WRAPPER):          @"XTERMCC_FRAMER_WRAPPER",
                          @(XTERMCC_LINK):                    @"XTERMCC_LINK",
                          @(XTERMCC_TEXT_BACKGROUND_COLOR):   @"XTERMCC_TEXT_BACKGROUND_COLOR",
                          @(XTERMCC_TEXT_FOREGROUND_COLOR):   @"XTERMCC_TEXT_FOREGROUND_COLOR",
                          @(XTERMCC_XTPUSHSGR):               @"XTERMCC_XTPUSHSGR",
                          @(XTERMCC_XTPOPSGR):                @"XTERMCC_XTPOPSGR",

                          @(ANSICSI_CHA):                     @"ANSICSI_CHA",
                          @(ANSICSI_VPA):                     @"ANSICSI_VPA",
                          @(ANSICSI_VPR):                     @"ANSICSI_VPR",
                          @(ANSICSI_ECH):                     @"ANSICSI_ECH",
                          @(ANSICSI_PRINT):                   @"ANSICSI_PRINT",
                          @(ANSICSI_SCP):                     @"ANSICSI_SCP",
                          @(ANSICSI_RCP):                     @"ANSICSI_RCP",
                          @(ANSICSI_CBT):                     @"ANSICSI_CBT",
                          @(ANSI_RIS):                        @"ANSI_RIS",
                          @(STRICT_ANSI_MODE):                @"STRICT_ANSI_MODE",
                          @(ITERM_USER_NOTIFICATION):                     @"ITERM_USER_NOTIFICATION",
                          @(DCS_TMUX_HOOK):                   @"DCS_TMUX_HOOK",
                          @(TMUX_LINE):                       @"TMUX_LINE",
                          @(TMUX_EXIT):                       @"TMUX_EXIT",
                          @(DCS_TMUX_CODE_WRAP):              @"DCS_TMUX_CODE_WRAP",
                          @(VT100CSI_DECSLRM_OR_ANSICSI_SCP): @"VT100CSI_DECSLRM_OR_ANSICSI_SCP",
                          @(DCS_REQUEST_TERMCAP_TERMINFO):    @"DCS_REQUEST_TERMCAP_TERMINFO",
                          @(DCS_SIXEL):                       @"DCS_SIXEL",
                          @(DCS_DECRQSS):                     @"DCS_DECRQSS",
                          @(DCS_DECRSPS_DECCIR):              @"DCS_DECRSPS_DECCIR",
                          @(DCS_DECRSPS_DECTABSR):            @"DCS_DECRSPS_DECTABSR",
                          @(DCS_XTSETTCAP):                   @"DCS_XTSETTCAP",
                          @(DCS_SSH_HOOK):                    @"DCS_SSH_HOOK",
                          @(SSH_INIT):                        @"SSH_INIT",
                          @(SSH_LINE):                        @"SSH_LINE",
                          @(SSH_UNHOOK):                      @"SSH_UNHOOK",
                          @(SSH_BEGIN):                       @"SSH_BEGIN",
                          @(SSH_END):                         @"SSH_END",
                          @(SSH_OUTPUT):                      @"SSH_OUTPUT",
                          @(SSH_TERMINATE):                   @"SSH_TERMINATE",
                          @(SSH_RECOVERY_BOUNDARY):           @"SSH_RECOVERY_BOUNDARY",
    };
    NSString *name = map[@(type)];
    if (name) {
        return name;
    } else {
        return [NSString stringWithFormat:@"%d", type];
    }
}

- (NSString *)description {
    NSMutableString *params = [NSMutableString string];
    if (_csi && _csi->count > 0) {
        [params appendString:@" params="];
        for (int i = 0; i < _csi->count; i++) {
            if (_csi->p[i] < 0) {
                [params appendFormat:@"[default];"];
            } else {
                [params appendFormat:@"%d;", _csi->p[i]];
            }
        }
    }
    if (_string) {
        [params appendFormat:@" string=“%@”", _string];
    }
    if (_asciiData.length) {
        [params appendFormat:@" asciiData=“%.*s”", _asciiData.length, _asciiData.buffer];
    }
    if (type == SSH_OUTPUT) {
        [params appendFormat:@" ssh-output=“%@” info=%@",
         [[[NSString alloc] initWithData:_savedData encoding:NSUTF8StringEncoding] autorelease],
         SSHInfoDescription(self.sshInfo)];
    }
    return [NSString stringWithFormat:@"<%@: %p type=%@%@>", self.class, self, [self codeName], params];
}

- (CSIParam *)csi {
    if (!_csi) {
        _csi = iTermCalloc(sizeof(*_csi), 1);
    }
    return _csi;
}

- (BOOL)isAscii {
    return type == VT100_ASCIISTRING;
}

- (BOOL)isStringType {
    return (type == VT100_STRING || type == VT100_ASCIISTRING);
}

- (void)setAsciiBytes:(char *)bytes length:(int)length {
    iTermAsciiDataSet(&_asciiData, bytes, length, &_screenChars);
}

- (AsciiData *)asciiData {
    return &_asciiData;
}

- (NSString *)stringForAsciiData {
    return [[[NSString alloc] initWithBytes:_asciiData.buffer
                                     length:_asciiData.length
                                   encoding:NSASCIIStringEncoding] autorelease];
}

- (ScreenChars *)screenChars {
    return &_screenChars;
}

- (void)translateFromScreenTerminal {
    switch (type) {
        case VT100CSI_SGR:
            if (self.csi) {
                [self translateSGRFromScreenTerminal];
            }
            break;
        case VT100CSI_DECSET:
        case VT100CSI_DECRST:
            [self translateDECSETFromScreenTerminal];
            break;
        default:
            break;
    }
}

// There is a lot more that can be done to perform this translation but remapping italic->inverse
// is particularly visible.
- (void)translateSGRFromScreenTerminal {
    for (int i = 0; i < self.csi->count; i++) {
        switch (self.csi->p[i]) {
            case 3:
                if ([iTermAdvancedSettingsModel convertItalicsToReverseVideoForTmux]) {
                    self.csi->p[i] = 7;
                }
                break;
            case 23:
                if ([iTermAdvancedSettingsModel convertItalicsToReverseVideoForTmux]) {
                    self.csi->p[i] = 27;
                }
                break;
        }
    }
}

- (void)translateDECSETFromScreenTerminal {
    for (int i = 0; i < self.csi->count; i++) {
        switch (self.csi->p[i]) {
            case 5:
                // screen doesn't support reversing the whole screen.
                self.csi->p[i] = -1;
                break;
        }
    }
}

- (VT100TerminalTokenType)type {
    return self->type;
}

- (void)setType:(VT100TerminalTokenType)newType {
    self->type = newType;
}

@end
