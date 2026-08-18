//
//  VT100SixelParser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/11/19.
//

#import "VT100SixelParser.h"

@implementation VT100SixelParser {
    NSMutableData *_accumulator;
    NSArray<NSString *> *_parameters;
    BOOL _esc;
    // Length of the ESC P [params] q header prefixed to _accumulator. Anything
    // beyond this is actual sixel payload.
    NSUInteger _headerLength;
}

- (instancetype)initWithParameters:(NSArray *)parameters {
    self = [super init];
    if (self) {
        _accumulator = [NSMutableData data];
        char escp[2] = "\x1bP";
        [_accumulator appendBytes:escp length:2];
        if (parameters.count) {
            NSString *joined = [parameters componentsJoinedByString:@";"];
            [_accumulator appendData:[joined dataUsingEncoding:NSUTF8StringEncoding]];
        }
        [_accumulator appendBytes:"q" length:1];
        _headerLength = _accumulator.length;
        _parameters = [parameters copy];
    }
    return self;
}

// YES if any sixel payload bytes have been accumulated after the header.
- (BOOL)hasBody {
    return _accumulator.length > _headerLength;
}

// Populate a DCS_SIXEL token with the accumulated image data.
- (void)fillSixelToken:(VT100Token *)result {
    result->type = DCS_SIXEL;
    result.savedData = [self combinedData];
}

- (NSString *)hookDescription {
    return @"[SIXEL]";
}

- (NSData *)combinedData {
    NSString *joined = [[_parameters componentsJoinedByString:@";"] stringByAppendingString:@"\n"];
    NSData *paramData = [joined dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *result = [paramData mutableCopy];
    [result appendData:_accumulator];
    return result;
}

// Return YES if it should unhook.
- (VT100DCSParserHookResult)handleInput:(iTermParserContext *)context
           support8BitControlCharacters:(BOOL)support8BitControlCharacters
                                  token:(VT100Token *)result {
    if (!iTermParserCanAdvance(context)) {
        result->type = VT100_WAIT;
        return VT100DCSParserHookResultCanReadAgain;
    }
    if (_esc) {
        // The ESC was consumed in a prior read, so it is no longer in this context
        // and cannot be backtracked over.
        return [self handleInputAfterESC:context token:result escInContext:NO] ? VT100DCSParserHookResultUnhook : VT100DCSParserHookResultCanReadAgain;
    }

    while (iTermParserCanAdvance(context)) {
        // Scan to ST
        switch (iTermParserPeek(context)) {
            case VT100CC_C1_ST:
                if (support8BitControlCharacters) {
                    iTermParserConsume(context);
                    [self fillSixelToken:result];
                    return VT100DCSParserHookResultUnhook;
                }
                break;
            case VT100CC_ESC:
                return [self handleInputBeginningWithEsc:context token:result] ? VT100DCSParserHookResultUnhook : VT100DCSParserHookResultCanReadAgain;
        }

        // Search for next ESC or ST.
        // TODO(issue 12259 follow-up): under 8-bit control characters this prefers a
        // C1 ST anywhere in the buffer even when an ESC comes first, so an ESC
        // terminator followed later by a stray 0x9c swallows the intervening bytes
        // into the accumulator. Use the minimum of the two offsets instead.
        int n = -1;
        if (support8BitControlCharacters) {
            n = iTermParserNumberOfBytesUntilCharacter(context, VT100CC_C1_ST);
        }
        if (n < 0) {
            n = iTermParserNumberOfBytesUntilCharacter(context, VT100CC_ESC);
        }

        if (n >= 0) {
            // Handle input up to the next ESC or ST.
            [self handleInputOfLength:n
                              context:context
                                token:result];
            continue;
        }

        // There is no forthcoming ESC or ST. Handle all the input.
        [self handleInputOfLength:iTermParserLength(context)
                          context:context
                            token:result];
    }
    return VT100DCSParserHookResultCanReadAgain;
}

- (BOOL)handleInputBeginningWithEsc:(iTermParserContext *)context
                              token:(VT100Token *)result {
    iTermParserConsume(context);
    _esc = YES;
    // The ESC was just consumed from this context, so it is available to backtrack
    // over along with the byte that follows it.
    return [self handleInputAfterESC:context token:result escInContext:YES];
}

// Return YES to leave sixel mode. |escInContext| is YES if the ESC that led here
// was consumed from the current context (and can therefore be backtracked over).
- (BOOL)handleInputAfterESC:(iTermParserContext *)context
                      token:(VT100Token *)result
               escInContext:(BOOL)escInContext {
    unsigned char c;
    const BOOL consumed = iTermParserTryConsume(context, &c);
    if (!consumed) {
        result->type = VT100_WAIT;
        return NO;
    }
    _esc = NO;
    if (c == '\\') {
        // A well-formed ST terminates the image.
        [self fillSixelToken:result];
        return YES;
    }

    // ESC followed by something other than backslash. Rather than discard the whole
    // image (as VT100_NOTSUPPORT would), render what we have and let the byte(s)
    // reparse as a fresh sequence. This matches how real hardware and xterm behave:
    // sixels are drawn incrementally, so an unexpected ESC just ends the string with
    // the pixels already emitted, and the ESC begins a new sequence. Two shapes
    // matter (see issue 12259):
    //   * ESC ESC \ (a doubled-up terminator): put back only the second ESC so the
    //     remaining ESC \ reparses as a harmless ST. Backtracking two would resurrect
    //     the stray backslash the discard bug used to print.
    //   * ESC <cseq> (an aborting escape sequence such as ESC [ 2 J): put back the
    //     whole ESC <cseq> so it reparses and executes. We can only do this when the
    //     leading ESC is still in this context; if it arrived in a prior read it is
    //     already gone and we accept losing it (the byte still reparses on its own).
    // This tolerance deliberately lives here rather than in VT100DCSParser's shared
    // dcsEscapeState, which treats ESC ESC literally for tmux passthrough wrapping
    // and must not be generalized.
    if (c == VT100CC_ESC || !escInContext) {
        iTermParserBacktrackBy(context, 1);
    } else {
        iTermParserBacktrackBy(context, 2);
    }

    if (self.hasBody) {
        [self fillSixelToken:result];
    } else {
        // No pixels were accumulated (e.g. binary output that merely happens to
        // contain ESC P ... q). Emit nothing rather than stamping a broken-image
        // glyph and paying a synchronous decode per fragment.
        result->type = VT100_NOTSUPPORT;
    }
    return YES;
}

- (void)handleInputOfLength:(int)length
                    context:(iTermParserContext *)context
                      token:(VT100Token *)result {
    [_accumulator appendBytes:iTermParserPeekRawBytes(context, length)
                       length:length];
    iTermParserAdvanceMultiple(context, length);
    result->type = VT100_WAIT;
}

@end

