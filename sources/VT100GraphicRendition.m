//
//  VT100GraphicRendition.m
//  iTerm2
//
//  Created by George Nachman on 3/19/25.
//

#import "VT100GraphicRendition.h"
#import "iTermParser.h"

void VT100GraphicRenditionInitialize(VT100GraphicRendition *rendition) {
    memset(rendition, 0, sizeof(*rendition));
    rendition->fgColorCode = ALTSEM_DEFAULT;
    rendition->fgColorMode = ColorModeAlternate;
    rendition->bgColorCode = ALTSEM_DEFAULT;
    rendition->bgColorMode = ColorModeAlternate;
}

VT100GraphicRenditionSideEffect VT100GraphicRenditionExecuteSGR(VT100GraphicRendition *rendition, CSIParam *csi, int i) {
    const int code = csi->p[i];
    switch (code) {
        case VT100CHARATTR_ALLOFF:
            memset(rendition, 0, sizeof(*rendition));
            return VT100GraphicRenditionSideEffectReset;

        case VT100CHARATTR_BOLD:
            rendition->bold = YES;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_FAINT:
            rendition->faint = YES;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_ITALIC:
            rendition->italic = YES;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_UNDERLINE: {
            rendition->underline = YES;

            int subs[VT100CSISUBPARAM_MAX];
            const int numberOfSubparameters = iTermParserGetAllCSISubparametersForParameter(csi, i, subs);
            if (numberOfSubparameters > 0) {
                switch (subs[0]) {
                    case 0:
                        rendition->underline = NO;
                        return VT100GraphicRenditionSideEffectNone;
                    case 1:
                        rendition->underlineStyle = VT100UnderlineStyleSingle;
                        return VT100GraphicRenditionSideEffectNone;
                    case 3:
                        rendition->underlineStyle = VT100UnderlineStyleCurly;
                        return VT100GraphicRenditionSideEffectNone;
                }
            } else {
                rendition->underlineStyle = VT100UnderlineStyleSingle;
            }
            return VT100GraphicRenditionSideEffectNone;
        }
        case VT100CHARATTR_BLINK:
            rendition->blink = YES;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_REVERSE:
            rendition->reversed = YES;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_INVISIBLE:
            rendition->invisible = YES;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_STRIKETHROUGH:
            rendition->strikethrough = YES;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_DOUBLE_UNDERLINE:
            rendition->underline = YES;
            rendition->underlineStyle = VT100UnderlineStyleDouble;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_NORMAL:
            rendition->faint = rendition->bold = NO;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_NOT_ITALIC:
            rendition->italic = NO;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_NOT_UNDERLINE:
            rendition->underline = NO;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_STEADY:
            rendition->blink = NO;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_POSITIVE:
            rendition->reversed = NO;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_VISIBLE:
            rendition->invisible = NO;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_NOT_STRIKETHROUGH:
            rendition->strikethrough = NO;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_FG_DEFAULT:
            rendition->fgColorCode = ALTSEM_DEFAULT;
            rendition->fgGreen = 0;
            rendition->fgBlue = 0;
            rendition->fgColorMode = ColorModeAlternate;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_BG_DEFAULT:
            rendition->bgColorCode = ALTSEM_DEFAULT;
            rendition->bgGreen = 0;
            rendition->bgBlue = 0;
            rendition->bgColorMode = ColorModeAlternate;
            return VT100GraphicRenditionSideEffectNone;

        case VT100CHARATTR_UNDERLINE_COLOR_DEFAULT:
            rendition->hasUnderlineColor = NO;
            return VT100GraphicRenditionSideEffectUpdateExternalAttributes;

        case VT100CHARATTR_UNDERLINE_COLOR: {
            int j = i;
            const VT100TerminalColorValue value = VT100TerminalColorValueFromCSI(csi, &j);
            if (value.red >= 0) {
                rendition->hasUnderlineColor = YES;
                rendition->underlineColor = value;
            }
            if (j == i) {
                return value.red >= 0 ? VT100GraphicRenditionSideEffectUpdateExternalAttributes : VT100GraphicRenditionSideEffectNone;
            } else if (j == i + 2) {
                return value.red >= 0 ? VT100GraphicRenditionSideEffectSkip2AndUpdateExternalAttributes : VT100GraphicRenditionSideEffectSkip2;
            } else if (j == i + 4) {
                return value.red >= 0 ? VT100GraphicRenditionSideEffectSkip4AndUpdateExternalAttributes : VT100GraphicRenditionSideEffectSkip4;
            } else {
                assert(NO);
                return VT100GraphicRenditionSideEffectNone;
            }
        }
        case VT100CHARATTR_FG_256: {
            int j = i;
            const VT100TerminalColorValue value = VT100TerminalColorValueFromCSI(csi, &j);
            if (value.red >= 0) {
                rendition->fgColorCode = value.red;
                rendition->fgGreen = value.green;
                rendition->fgBlue = value.blue;
                rendition->fgColorMode = value.mode;
            }
            if (j == i) {
                return value.red >= 0 ? VT100GraphicRenditionSideEffectUpdateExternalAttributes : VT100GraphicRenditionSideEffectNone;
            } else if (j == i + 2) {
                return value.red >= 0 ? VT100GraphicRenditionSideEffectSkip2AndUpdateExternalAttributes : VT100GraphicRenditionSideEffectSkip2;
            } else if (j == i + 4) {
                return value.red >= 0 ? VT100GraphicRenditionSideEffectSkip4AndUpdateExternalAttributes : VT100GraphicRenditionSideEffectSkip4;
            } else {
                assert(NO);
                return VT100GraphicRenditionSideEffectNone;
            }

        }
        case VT100CHARATTR_BG_256: {
            int j = i;
            const VT100TerminalColorValue value = VT100TerminalColorValueFromCSI(csi, &j);
            if (value.red >= 0) {
                rendition->bgColorCode = value.red;
                rendition->bgGreen = value.green;
                rendition->bgBlue = value.blue;
                rendition->bgColorMode = value.mode;
            }
            if (j == i) {
                return value.red >= 0 ? VT100GraphicRenditionSideEffectUpdateExternalAttributes : VT100GraphicRenditionSideEffectNone;
            } else if (j == i + 2) {
                return value.red >= 0 ? VT100GraphicRenditionSideEffectSkip2AndUpdateExternalAttributes : VT100GraphicRenditionSideEffectSkip2;
            } else if (j == i + 4) {
                return value.red >= 0 ? VT100GraphicRenditionSideEffectSkip4AndUpdateExternalAttributes : VT100GraphicRenditionSideEffectSkip4;
            } else {
                assert(NO);
                return VT100GraphicRenditionSideEffectNone;
            }
        }
        default:
            // 8 color support
            if (code >= VT100CHARATTR_FG_BLACK &&
                code <= VT100CHARATTR_FG_WHITE) {
                rendition->fgColorCode = code - VT100CHARATTR_FG_BASE - COLORCODE_BLACK;
                rendition->fgGreen = 0;
                rendition->fgBlue = 0;
                rendition->fgColorMode = ColorModeNormal;
            } else if (code >= VT100CHARATTR_BG_BLACK &&
                       code <= VT100CHARATTR_BG_WHITE) {
                rendition->bgColorCode = code - VT100CHARATTR_BG_BASE - COLORCODE_BLACK;
                rendition->bgGreen = 0;
                rendition->bgBlue = 0;
                rendition->bgColorMode = ColorModeNormal;
            }
            // 16 color support
            if (code >= VT100CHARATTR_FG_HI_BLACK &&
                code <= VT100CHARATTR_FG_HI_WHITE) {
                rendition->fgColorCode = code - VT100CHARATTR_FG_HI_BASE - COLORCODE_BLACK + 8;
                rendition->fgGreen = 0;
                rendition->fgBlue = 0;
                rendition->fgColorMode = ColorModeNormal;
            } else if (code >= VT100CHARATTR_BG_HI_BLACK &&
                       code <= VT100CHARATTR_BG_HI_WHITE) {
                rendition->bgColorCode = code - VT100CHARATTR_BG_HI_BASE - COLORCODE_BLACK + 8;
                rendition->bgGreen = 0;
                rendition->bgBlue = 0;
                rendition->bgColorMode = ColorModeNormal;
            }
            return VT100GraphicRenditionSideEffectNone;
    }
}

// The actual spec for this is called ITU T.416-199303
// You can download it for free! If you prefer to spend money, ISO/IEC 8613-6
// is supposedly the same thing.
//
// Here's a sad story about CSI 38:2, which is used to do 24-bit color.
//
// Lots of terminal emulators, iTerm2 included, misunderstood the spec. That's
// easy to understand if you read it, which I can't recommend doing unless
// you're looking for inspiration for your next Bulwer-Lytton Fiction Contest
// entry.
//
// See issue 6377 for more context.
//
// Ignoring color types we don't support like CMYK, the spec says to do this:
// CSI 38:2:[color space]:[red]:[green]:[blue]:[unused]:[tolerance]:[tolerance colorspace]
//
// Everything after [blue] is optional. Values are decimal numbers in 0...255.
//
// Unfortunately, what was implemented for a long time was this:
// CSI 38:2:[red]:[green]:[blue]:[unused]:[tolerance]:[tolerance colorspace]
//
// And for xterm compatibility, the following was also accepted:
// CSI 38;2;[red];[green];[blue]
//
// The New Order
// -------------
// Tolerance never did anything, so we'll accept this non-standards compliant
// code, which people use:
// CSI 38:2:[red]:[green]:[blue]
//
// As well as the following forms:
// CSI 38:2:[colorspace]:[red]:[green]:[blue]
// CSI 38:2:[colorspace]:[red]:[green]:[blue]:<one or more additional colon-delimited arguments, all ignored>
// CSI 38;2;[red];[green];[blue]   // Notice semicolons in place of colons here
//
// NOTE: If you change this you must also update -sgrCodesForGraphicRendition:
VT100TerminalColorValue VT100TerminalColorValueFromCSI(CSIParam *csi, int *index) {
    const int i = *index;
    int subs[VT100CSISUBPARAM_MAX];
    const int numberOfSubparameters = iTermParserGetAllCSISubparametersForParameter(csi, i, subs);
    if (numberOfSubparameters > 0) {
        // Preferred syntax using colons to delimit subparameters
        if (numberOfSubparameters >= 2 && subs[0] == 5) {
            // CSI 38:5:P m
            return (VT100TerminalColorValue){
                .red = subs[1],
                .green = 0,
                .blue = 0,
                .mode = ColorModeNormal
            };
        }
        if (numberOfSubparameters >= 4 && subs[0] == 2) {
            // 24-bit color
            if (numberOfSubparameters >= 5) {
                // Spec-compliant. Likely rarely used in 2017.
                // CSI 38:2:colorspace:R:G:B m
                // TODO: Respect the color space argument. See ITU-T Rec. T.414,
                // but good luck actually finding the colour space IDs.
                return (VT100TerminalColorValue){
                    .red = subs[2],
                    .green = subs[3],
                    .blue = subs[4],
                    .mode = ColorMode24bit
                };
            }
            // Misinterpretation compliant.
            // CSI 38:2:R:G:B m  <- misinterpretation compliant
            return (VT100TerminalColorValue) {
                .red = subs[1],
                .green = subs[2],
                .blue = subs[3],
                .mode = ColorMode24bit
            };
        }
        return (VT100TerminalColorValue) {
            .red = -1,
            .green = -1,
            .blue = -1,
            .mode = ColorMode24bit
        };
    }
    if (csi->count - i >= 3 && csi->p[i + 1] == 5) {
        // For 256-color mode (indexed) use this for the foreground:
        // CSI 38;5;N m
        // where N is a value between 0 and 255. See the colors described in screen_char_t
        // in the comments for fgColorCode.
        *index += 2;
        return (VT100TerminalColorValue) {
            .red = csi->p[i + 2],
            .green = 0,
            .blue = 0,
            .mode = ColorModeNormal
        };
    }
    if (csi->count - i >= 5 && csi->p[i + 1] == 2) {
        // CSI 38;2;R;G;B m
        // Hack for xterm compatibility
        // 24-bit color support
        *index += 4;
        return (VT100TerminalColorValue) {
            .red = csi->p[i + 2],
            .green = csi->p[i + 3],
            .blue = csi->p[i + 4],
            .mode = ColorMode24bit
        };
    }
    return (VT100TerminalColorValue) {
        .red = -1,
        .green = -1,
        .blue = -1,
        .mode = ColorMode24bit
    };
}

VT100GraphicRendition VT100GraphicRenditionFromCharacter(const screen_char_t *c, iTermExternalAttribute *attr) {
    return (VT100GraphicRendition) {
        .bold = c->bold,
        .blink = c->blink,
        .invisible = c->invisible,
        .underline = c->underline,
        .underlineStyle = c->underlineStyle,
        .strikethrough = c->strikethrough,
        .reversed = c->inverse,
        .faint = c->faint,
        .italic = c->italic,

        .fgColorCode = c->foregroundColor,
        .fgGreen = c->fgGreen,
        .fgBlue = c->fgBlue,
        .fgColorMode = c->foregroundColorMode,

        .bgColorCode = c->backgroundColor,
        .bgGreen = c->bgGreen,
        .bgBlue = c->bgBlue,
        .bgColorMode = c->backgroundColorMode,

        .hasUnderlineColor = attr.hasUnderlineColor,
        .underlineColor = attr.underlineColor,
    };
}

void VT100GraphicRenditionUpdateForeground(const VT100GraphicRendition *rendition,
                                           BOOL applyReverse,
                                           BOOL protectedMode,
                                           screen_char_t *c) {
    if (applyReverse) {
        if (rendition->reversed) {
            if (rendition->bgColorMode == ColorModeAlternate &&
                rendition->bgColorCode == ALTSEM_DEFAULT) {
                c->foregroundColor = ALTSEM_REVERSED_DEFAULT;
            } else {
                c->foregroundColor = rendition->bgColorCode;
            }
            c->fgGreen = rendition->bgGreen;
            c->fgBlue = rendition->bgBlue;
            c->foregroundColorMode = rendition->bgColorMode;
        } else {
            c->foregroundColor = rendition->fgColorCode;
            c->fgGreen = rendition->fgGreen;
            c->fgBlue = rendition->fgBlue;
            c->foregroundColorMode = rendition->fgColorMode;
        }
        c->image = NO;
        c->virtualPlaceholder = NO;
    } else {
        c->foregroundColor = rendition->fgColorCode;
        c->fgGreen = rendition->fgGreen;
        c->fgBlue = rendition->fgBlue;
        c->foregroundColorMode = rendition->fgColorMode;

    }
    c->bold = rendition->bold;
    c->faint = rendition->faint;
    c->italic = rendition->italic;
    c->underline = rendition->underline;
    c->strikethrough = rendition->strikethrough;
    c->underlineStyle = rendition->underlineStyle;
    c->blink = rendition->blink;
    c->invisible = rendition->invisible;
    c->image = NO;
    c->virtualPlaceholder = NO;
    c->inverse = rendition->reversed;
    c->guarded = protectedMode;
    c->rtlStatus = RTLStatusUnknown;
    c->unused = 0;
}

void VT100GraphicRenditionUpdateBackground(const VT100GraphicRendition *rendition,
                                           BOOL applyReverse,
                                           screen_char_t *c) {
    if (applyReverse) {
        if (rendition->reversed) {
            if (rendition->fgColorMode == ColorModeAlternate &&
                rendition->fgColorCode == ALTSEM_DEFAULT) {
                c->backgroundColor = ALTSEM_REVERSED_DEFAULT;
            } else {
                c->backgroundColor = rendition->fgColorCode;
            }
            c->bgGreen = rendition->fgGreen;
            c->bgBlue = rendition->fgBlue;
            c->backgroundColorMode = rendition->fgColorMode;
        } else {
            c->backgroundColor = rendition->bgColorCode;
            c->bgGreen = rendition->bgGreen;
            c->bgBlue = rendition->bgBlue;
            c->backgroundColorMode = rendition->bgColorMode;
        }
    } else {
        c->backgroundColor = rendition->bgColorCode;
        c->bgGreen = rendition->bgGreen;
        c->bgBlue = rendition->bgBlue;
        c->backgroundColorMode = rendition->bgColorMode;
    }
}

