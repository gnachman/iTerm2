//
//  VT100Token.m
//  iTerm
//
//  Created by George Nachman on 3/3/14.
//
//

#import "VT100Token.h"
#import "DebugLogging.h"
#include <stdlib.h>

static iTermObjectPool *gPool;

@interface VT100Token ()
@property(nonatomic, readwrite) CSIParam *csi;
@end

@implementation VT100Token {
    AsciiData _asciiData;
    ScreenChars _screenChars;
}

+ (void)initialize {
    gPool = [[iTermObjectPool alloc] initWithClass:self collections:20 objectsPerCollection:100];
}

+ (instancetype)token {
    if (gDebugLogging) {
        static int i;
        if (i % 100000 == 0) {
            DLog(@"%@", gPool);
        }
        i++;
    }
    return (VT100Token *)[gPool pooledObject];
}

+ (instancetype)tokenForControlCharacter:(unsigned char)controlCharacter {
    VT100Token *token = (VT100Token *)[gPool pooledObject];
    token->type = controlCharacter;
    return token;
}

- (void)destroyPooledObject {
    if (_csi) {
        free(_csi);
        _csi = NULL;
    }
    
    [_string release];
    _string = nil;
    
    [_kvpKey release];
    _kvpKey = nil;
    
    [_kvpValue release];
    _kvpValue = nil;
    
    [_savedData release];
    _savedData = nil;
    
    if (_asciiData.buffer != _asciiData.staticBuffer) {
        free(_asciiData.buffer);
    }
    if (_asciiData.screenChars &&
        _asciiData.screenChars->buffer != _asciiData.screenChars->staticBuffer) {
        free(_asciiData.screenChars->buffer);
    }
    _asciiData.buffer = NULL;
    _asciiData.length = 0;
    _asciiData.screenChars = NULL;
    
    type = 0;
    code = 0;
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
                          @(VT100CSI_CUU):                    @"VT100CSI_CUU",
                          @(VT100CSI_DA):                     @"VT100CSI_DA",
                          @(VT100CSI_DA2):                    @"VT100CSI_DA2",
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
                          @(VT100CSI_SM):                     @"VT100CSI_SM",
                          @(VT100CSI_TBC):                    @"VT100CSI_TBC",
                          @(VT100CSI_DECSCUSR):               @"VT100CSI_DECSCUSR",
                          @(VT100CSI_DECSTR):                 @"VT100CSI_DECSTR",
                          @(VT100CSI_DECDSR):                 @"VT100CSI_DECDSR",
                          @(VT100CSI_SET_MODIFIERS):          @"VT100CSI_SET_MODIFIERS",
                          @(VT100CSI_RESET_MODIFIERS):        @"VT100CSI_RESET_MODIFIERS",
                          @(VT100CSI_DECSLRM):                @"VT100CSI_DECSLRM",
                          @(XTERMCC_WIN_TITLE):               @"XTERMCC_WIN_TITLE",
                          @(XTERMCC_ICON_TITLE):              @"XTERMCC_ICON_TITLE",
                          @(XTERMCC_WINICON_TITLE):           @"XTERMCC_WINICON_TITLE",
                          @(VT100CSI_ICH):                    @"VT100CSI_ICH",
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
                          @(XTERMCC_SET_RGB):                 @"XTERMCC_SET_RGB",
                          @(XTERMCC_PROPRIETARY_ETERM_EXT):   @"XTERMCC_PROPRIETARY_ETERM_EXT",
                          @(XTERMCC_SET_PALETTE):             @"XTERMCC_SET_PALETTE",
                          @(XTERMCC_SET_KVP):                 @"XTERMCC_SET_KVP",
                          @(XTERMCC_MULTITOKEN_HEADER_SET_KVP): @"XTERMCC_MULTITOKEN_HEADER_SET_KVP",
                          @(XTERMCC_MULTITOKEN_BODY):         @"XTERMCC_MULTITOKEN_BODY",
                          @(XTERMCC_MULTITOKEN_END):          @"XTERMCC_MULTITOKEN_END",
                          @(XTERMCC_PASTE64):                 @"XTERMCC_PASTE64",
                          @(XTERMCC_FINAL_TERM):              @"XTERMCC_FINAL_TERM",
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
                          @(ITERM_GROWL):                     @"ITERM_GROWL",
                          @(DCS_TMUX_HOOK):                   @"DCS_TMUX_HOOK",
                          @(TMUX_LINE):                       @"TMUX_LINE",
                          @(TMUX_EXIT):                       @"TMUX_EXIT",
                          @(DCS_TMUX_CODE_WRAP):              @"DCS_TMUX_CODE_WRAP",
                          @(VT100CSI_DECSLRM_OR_ANSICSI_SCP): @"VT100CSI_DECSLRM_OR_ANSICSI_SCP",
                          @(DCS_REQUEST_TERMCAP_TERMINFO):    @"DCS_REQUEST_TERMCAP_TERMINFO", };
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
    return [NSString stringWithFormat:@"<%@: %p type=%@%@>", self.class, self, [self codeName], params];
}

- (CSIParam *)csi {
    if (!_csi) {
        _csi = calloc(sizeof(*_csi), 1);
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
    assert(_asciiData.buffer == NULL);
    
    _asciiData.length = length;
    if (length > sizeof(_asciiData.staticBuffer)) {
        _asciiData.buffer = malloc(length);
    } else {
        _asciiData.buffer = _asciiData.staticBuffer;
    }
    memcpy(_asciiData.buffer, bytes, length);
    
    [self preInitializeScreenChars];
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

- (void)preInitializeScreenChars {
    // TODO: Expand this beyond just ascii characters.
    if (_asciiData.length > kStaticScreenCharsCount) {
        _screenChars.buffer = calloc(_asciiData.length, sizeof(screen_char_t));
    } else {
        _screenChars.buffer = _screenChars.staticBuffer;
        memset(_screenChars.buffer, 0, _asciiData.length * sizeof(screen_char_t));
    }
    for (int i = 0; i < _asciiData.length; i++) {
        _screenChars.buffer[i].code = _asciiData.buffer[i];
    }
    _screenChars.length = _asciiData.length;
    _asciiData.screenChars = &_screenChars;
}

@end
