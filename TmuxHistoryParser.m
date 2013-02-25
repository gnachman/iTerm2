//
//  TmuxHistoryParser.m
//  iTerm
//
//  Created by George Nachman on 11/29/11.
//

#import "TmuxHistoryParser.h"
#import "ScreenChar.h"
#import "VT100Screen.h"
#import "VT100Terminal.h"

@implementation TmuxHistoryParser

+ (TmuxHistoryParser *)sharedInstance
{
    static TmuxHistoryParser *instance;
    if (!instance) {
        instance = [[TmuxHistoryParser alloc] init];
    }
    return instance;
}

// Returns nil on error
- (NSData *)dataForHistoryLine:(NSString *)hist
                  withTerminal:(VT100Terminal *)terminal
        ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth
{
    screen_char_t *screenChars;
    NSMutableData *result = [NSMutableData data];
    [terminal putStreamData:[hist dataUsingEncoding:NSUTF8StringEncoding]];
    VT100TCC token;
    token = [terminal getNextToken];
    while (token.type != VT100_WAIT &&
           token.type != VT100CC_NULL) {
        if (token.type != VT100_NOTSUPPORT) {
            int len = 0;
            switch (token.type) {
                case VT100_STRING:
                case VT100_ASCIISTRING:
                    screenChars = malloc(sizeof(screen_char_t) * token.u.string.length);
                    StringToScreenChars(token.u.string,
                                        screenChars,
                                        [terminal foregroundColorCode],
                                        [terminal backgroundColorCode],
                                        &len,
                                        ambiguousIsDoubleWidth,
                                        NULL);
                    if ([terminal charset]) {
                        TranslateCharacterSet(screenChars, len);
                    }
                    [result appendBytes:screenChars
                                 length:sizeof(screen_char_t) * token.u.string.length];
                    free(screenChars);
                    break;

                case VT100CSI_SGR:
                    break;
                case VT100CC_SO:
                    break;
                case VT100CC_SI:
                    break;
            }
        }
        token = [terminal getNextToken];
    }

    return result;
}

// Return an NSArray of NSData's. Each NSData is an array of screen_char_t's,
// with the last element in each being the newline. Returns nil on error.
- (NSArray *)parseDumpHistoryResponse:(NSString *)response
               ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth
{
    NSArray *lines = [response componentsSeparatedByString:@"\n"];
    NSMutableArray *screenLines = [NSMutableArray array];
    VT100Terminal *terminal = [[[VT100Terminal alloc] init] autorelease];
    for (NSString *line in lines) {
        NSData *data = [self dataForHistoryLine:line
                                   withTerminal:terminal
                         ambiguousIsDoubleWidth:ambiguousIsDoubleWidth];
        if (!data) {
            return nil;
        }
        [screenLines addObject:data];
    }

    return screenLines;
}

@end
