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
        _parameters = [parameters copy];
    }
    return self;
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
        return [self handleInputAfterESC:context token:result] ? VT100DCSParserHookResultUnhook : VT100DCSParserHookResultCanReadAgain;
    }

    while (iTermParserCanAdvance(context)) {
        // Scan to ST
        switch (iTermParserPeek(context)) {
            case VT100CC_C1_ST:
                if (support8BitControlCharacters) {
                    iTermParserConsume(context);
                    result->type = DCS_SIXEL;
                    result.savedData = [self combinedData];
                    return VT100DCSParserHookResultUnhook;
                }
                break;
            case VT100CC_ESC:
                return [self handleInputBeginningWithEsc:context token:result] ? VT100DCSParserHookResultUnhook : VT100DCSParserHookResultCanReadAgain;
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
    return VT100DCSParserHookResultCanReadAgain;
}

- (BOOL)handleInputBeginningWithEsc:(iTermParserContext *)context
                              token:(VT100Token *)result {
    iTermParserConsume(context);
    _esc = YES;
    return [self handleInputAfterESC:context token:result];
}

// Return YES to leave sixel mode.
- (BOOL)handleInputAfterESC:(iTermParserContext *)context
                      token:(VT100Token *)result {
    unsigned char c;
    const BOOL consumed = iTermParserTryConsume(context, &c);
    if (!consumed) {
        result->type = VT100_WAIT;
        return NO;
    }
    _esc = NO;
    if (c != '\\') {
        // esc + something unexpected. Broken sequence.
        result->type = VT100_NOTSUPPORT;
        return YES;
    }

    result->type = DCS_SIXEL;
    result.savedData = [self combinedData];
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

