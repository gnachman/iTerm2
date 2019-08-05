//
//  VT100SixelParser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/11/19.
//

#import "VT100SixelParser.h"
#import "sixel.h"

@implementation VT100SixelParser {
    sixel_decoder_t *_decoder;
    NSMutableData *_accumulator;
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

        SIXELSTATUS status = sixel_decoder_new(&_decoder, NULL);
        if (status != SIXEL_OK) {
            return nil;
        }

        [parameters enumerateObjectsUsingBlock:^(NSString * _Nonnull value, NSUInteger index, BOOL * _Nonnull stop) {
            sixel_decoder_setopt(self->_decoder,
                                 index,
                                 value.UTF8String);
        }];
    }
    return self;
}

- (NSString *)hookDescription {
    return @"[SIXEL]";
}

// Return YES if it should unhook.
- (BOOL)handleInput:(iTermParserContext *)context
support8BitControlCharacters:(BOOL)support8BitControlCharacters
              token:(VT100Token *)result {
    if (!iTermParserCanAdvance(context)) {
        result->type = VT100_WAIT;
        return NO;
    }

    while (iTermParserCanAdvance(context)) {
        // Scan to ST
        switch (iTermParserPeek(context)) {
            case VT100CC_C1_ST:
                if (support8BitControlCharacters) {
                    iTermParserConsume(context);
                    result->type = DCS_SIXEL;
                    result.savedData = _accumulator;
                    return YES;
                }
                break;
            case VT100CC_ESC:
                return [self handleInputBeginningWithEsc:context token:result];
        }

        // Search for next ESC or ST.
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
    return NO;
}

// Return YES to leave sixel mode.
- (BOOL)handleInputBeginningWithEsc:(iTermParserContext *)context
                              token:(VT100Token *)result {
    iTermParserConsume(context);
    unsigned char c;
    const BOOL consumed = iTermParserTryConsume(context, &c);
    if (!consumed) {
        iTermParserBacktrack(context);
        result->type = VT100_WAIT;
        return NO;
    }
    if (c != '\\') {
        // esc + something unexpected. Broken sequence.
        result->type = VT100_NOTSUPPORT;
        return YES;
    }

    result->type = DCS_SIXEL;
    result.savedData = _accumulator;
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

