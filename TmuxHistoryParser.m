//
//  TmuxHistoryParser.m
//  iTerm
//
//  Created by George Nachman on 11/29/11.
//

#import "TmuxHistoryParser.h"
#import "ScreenChar.h"
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
// TODO: Test with italics
- (NSData *)dataForHistoryLine:(NSString *)hist
                  withTerminal:(VT100Terminal *)terminal
        ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth
{
    screen_char_t *screenChars;
    NSMutableData *result = [NSMutableData data];
    [terminal putStreamData:[hist dataUsingEncoding:NSUTF8StringEncoding]];

    while ([terminal parseNextToken]) {
        NSString *string = [terminal lastTokenString];
        if (string) {
            // Allocate double space in case they're all double-width characters.
            screenChars = malloc(sizeof(screen_char_t) * 2 * string.length);
            int len = 0;
            StringToScreenChars(string,
                                screenChars,
                                [terminal foregroundColorCode],
                                [terminal backgroundColorCode],
                                &len,
                                ambiguousIsDoubleWidth,
                                NULL);
            if ([terminal lastTokenWasASCII] && [terminal charset]) {
                ConvertCharsToGraphicsCharset(screenChars, len);
            }
            [result appendBytes:screenChars
                         length:sizeof(screen_char_t) * len];
            free(screenChars);
        }
    }

    return result;
}

// Return an NSArray of NSData's. Each NSData is an array of screen_char_t's,
// with the last element in each being the newline. Returns nil on error.
- (NSArray *)parseDumpHistoryResponse:(NSString *)response
               ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth
{
    if (![response length]) {
        return [NSArray array];
    }
    NSArray *lines = [response componentsSeparatedByString:@"\n"];
    NSMutableArray *screenLines = [NSMutableArray array];
    VT100Terminal *terminal = [[[VT100Terminal alloc] init] autorelease];
    [terminal setEncoding:NSUTF8StringEncoding];
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
