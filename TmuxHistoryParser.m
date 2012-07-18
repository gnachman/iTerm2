//
//  TmuxHistoryParser.m
//  iTerm
//
//  Created by George Nachman on 11/29/11.
//

#import "TmuxHistoryParser.h"
#import "ScreenChar.h"

typedef struct {
    int attr;
    int flags;
    int fg;
    int bg;
    screen_char_t prototype;
    BOOL isDwcPadding;
} HistoryParseContext;

// -- begin section copied from tmux.h --
/* Grid attributes. */
#define GRID_ATTR_BRIGHT 0x1
#define GRID_ATTR_DIM 0x2
#define GRID_ATTR_UNDERSCORE 0x4
#define GRID_ATTR_BLINK 0x8
#define GRID_ATTR_REVERSE 0x10
#define GRID_ATTR_HIDDEN 0x20
#define GRID_ATTR_ITALICS 0x40
#define GRID_ATTR_CHARSET 0x80  /* alternative character set */

/* Grid flags. */
#define GRID_FLAG_FG256 0x1
#define GRID_FLAG_BG256 0x2
#define GRID_FLAG_PADDING 0x4
#define GRID_FLAG_UTF8 0x8

/* Grid line flags. */
#define GRID_LINE_WRAPPED 0x1
// -- end section copied from tmux.h --


@implementation TmuxHistoryParser

+ (TmuxHistoryParser *)sharedInstance
{
    static TmuxHistoryParser *instance;
    if (!instance) {
        instance = [[TmuxHistoryParser alloc] init];
    }
    return instance;
}

- (screen_char_t)prototypeScreenCharWithAttributes:(int)attributes
                                             flags:(int)flags
                                                fg:(int)fg
                                                bg:(int)bg
{
    screen_char_t temp;
    memset(&temp, 0, sizeof(temp));

    if (fg == 8) {
        // Default fg
        temp.foregroundColor = ALTSEM_FG_DEFAULT;
        temp.alternateForegroundSemantics = YES;
    } else {
        temp.foregroundColor = fg;
        temp.alternateForegroundSemantics = NO;
        // TODO: GRID_ATTR_DIM not supported
    }
    if (bg == 8) {
        temp.backgroundColor = ALTSEM_BG_DEFAULT;
        temp.alternateBackgroundSemantics = YES;
    } else {
        temp.backgroundColor = bg;
        temp.alternateBackgroundSemantics = NO;
    }

    if (attributes & GRID_ATTR_BRIGHT) {
        temp.bold = YES;
    }
    if (attributes & GRID_ATTR_UNDERSCORE) {
        temp.underline = YES;
    }
    if (attributes & GRID_ATTR_BLINK) {
        temp.blink = YES;
    }
    if (attributes & GRID_ATTR_REVERSE) {
        int x = temp.foregroundColor;
        temp.foregroundColor = temp.backgroundColor;
        temp.backgroundColor = x;

        x = temp.alternateForegroundSemantics;
        temp.alternateForegroundSemantics = temp.alternateBackgroundSemantics;
        temp.alternateBackgroundSemantics = x;
    }

    if (attributes & GRID_ATTR_HIDDEN) {
        // TODO not supported (SGR 8)
    }
    if (attributes & GRID_ATTR_ITALICS) {
        temp.italic = YES;
    }
    if (attributes & GRID_ATTR_CHARSET) {
        // TODO not supported
    }
    return temp;
}

// Convert a hex digit at s into an int placing it in *out and returning the number
// of characters used in the conversion.
static int consume_hex(const char *s, int *out)
{
    char const *endptr = s;
    *out = strtol(s, (char**) &endptr, 16);
    return endptr - s;
}

- (NSData *)dataForHistoryLine:(NSString *)hist
                   withContext:(HistoryParseContext *)ctx
{
    NSMutableData *result = [NSMutableData data];
    screen_char_t lastChar;
    BOOL softEol = NO;
    if ([hist hasSuffix:@"+"]) {
        softEol = YES;
        hist = [hist substringWithRange:NSMakeRange(0, hist.length - 1)];
    }

    const char *s = [hist UTF8String];
    for (int i = 0; s[i]; ) {
        if (s[i] == ':') {
//            NSLog(@"found a : at %d", i);
            // Context update follows
            i++;
            int values[4];
            for (int j = 0; j < 4; j++) {
                int n = consume_hex(s + i, &values[j]);
                i += n;
                if (s[i] == ',') {
                    i++;
                } else {
                    return nil;
                }
            }
            ctx->prototype = [self prototypeScreenCharWithAttributes:values[0]
                                                               flags:values[1]
                                                                  fg:values[2]
                                                                  bg:values[3]];
            // attr, flags, fg, bg
            if (values[1] & GRID_FLAG_PADDING) {
                ctx->isDwcPadding = YES;
            } else {
                ctx->isDwcPadding = NO;
            }
        } else if (s[i] == '*') {
 //           NSLog(@"found a * at %d", i);
            i++;
            NSInteger repeats;
            // We have a "*<number> " sequence. Scan the number.
            if ([[NSScanner scannerWithString:[NSString stringWithUTF8String:s + i]] scanInteger:&repeats]) {
                // Append the last character repeats-1 times.
                for (int j = 0; j < repeats - 1; j++) {
                    [result appendBytes:&lastChar length:sizeof(screen_char_t)];
                }
                // Advance up to and then past the terminal space, if present.
                while (s[i] && s[i] != ' ') {
                    i++;
                }
                if (s[i] == ' ') {
                    i++;
                } else {
                    NSLog(@"malformed dump history lacks a space after *n: <<%@>>", hist);
                    return nil;
                }
            } else {
                NSLog(@"malformed dump history lacks a number after *: <<%@>>", hist);
                return nil;
            }
        }

        // array of 2-digit hex values interspersed with [ 2 digit hex values ].
        BOOL utf8 = NO;
        NSMutableData *utf8Buffer = [NSMutableData data];
        while (s[i] == '[' ||
               s[i] == ']' ||
               (ishexnumber(s[i]) && ishexnumber(s[i + 1]))) {
//            NSLog(@"top of while loop: i=%d", i);
            if (s[i] == '[') {
//                NSLog(@"-- begin utf 8 --");
                if (s[i+1] && s[i+2] && s[i+3]) {
                    utf8 = YES;
                    [utf8Buffer setLength:0];
                } else {
                    NSLog(@"Malformed text after [ in history");
                    return nil;
                }
                i++;
            } else if (s[i] == ']') {
//                NSLog(@"-- end utf 8 --");
                if (utf8) {
                    utf8 = NO;
                    NSString *stringValue = [[[NSString alloc] initWithData:utf8Buffer encoding:NSUTF8StringEncoding] autorelease];
                    ctx->prototype.code = GetOrSetComplexChar(stringValue);
                    ctx->prototype.complexChar = 1;
                    lastChar = ctx->prototype;
                    [result appendBytes:&ctx->prototype length:sizeof(screen_char_t)];
                } else {
                    NSLog(@"] without [ in history");
                    return nil;
                }
                i++;
                continue;
            } else {
                // Read a hex digit
                unsigned scanned;
                if ([[NSScanner scannerWithString:[NSString stringWithFormat:@"%c%c", s[i], s[i+1]]] scanHexInt:&scanned]) {
//                    NSLog(@"scanned %@", [NSString stringWithFormat:@"%c%c", s[i], s[i+1]]);
                    if (utf8) {
                        char c = scanned;
                        [utf8Buffer appendBytes:&c length:1];
                    } else {
                        if (ctx->isDwcPadding) {
                            ctx->prototype.code = DWC_RIGHT;
                        } else {
                            ctx->prototype.code = scanned;
                        }
                        ctx->prototype.complexChar = 0;
                        // Skip DWC_RIGHT if it's the first thing in a line. It would
                        // be better to set the last char of the previous line to DWC_SKIP
                        // and the eol to EOF_DWC, but I think tmux prevents this from
                        // happening anyway.
                        if (result.length > 0 || ctx->prototype.code != DWC_RIGHT) {
                            lastChar = ctx->prototype;
                            [result appendBytes:&ctx->prototype length:sizeof(screen_char_t)];
                        }
                    }
                    i += 2;
                } else {
                    NSLog(@"Malformed hex array at %d: \"%c%c\" (%d %d)", i, s[i], s[i+1], (int) s[i], (int) s[i+1]);
                    return nil;
                }
            }
        }
        if (utf8) {
            NSLog(@"Malformed history line has unclosed utf8 at %d: %@", i, hist);
            return nil;
        }
    }

    screen_char_t eolSct;
    if (softEol) {
        eolSct.code = EOL_SOFT;
    } else {
        eolSct.code = EOL_HARD;
    }
    [result appendBytes:&eolSct length:sizeof(eolSct)];

    return result;
}

// Return an NSArray of NSData's. Each NSData is an array of screen_char_t's,
// with the last element in each being the newline.
- (NSArray *)parseDumpHistoryResponse:(NSString *)response
{
    NSArray *lines = [response componentsSeparatedByString:@"\n"];
    NSMutableArray *screenLines = [NSMutableArray array];
    HistoryParseContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    for (NSString *line in lines) {
        [screenLines addObject:[self dataForHistoryLine:line
                                            withContext:&ctx]];
    }

    return screenLines;
}

@end
