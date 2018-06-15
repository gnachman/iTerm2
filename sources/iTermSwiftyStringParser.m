//
//  iTermSwiftyStringParser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/13/18.
//

#import "iTermSwiftyStringParser.h"

typedef enum {
    SWIFTY_STATE_LITERAL,
    SWIFTY_STATE_LITERAL_ESC,
    SWIFTY_STATE_EXPR,
    SWIFTY_STATE_EXPR_STR,
    SWIFTY_STATE_EXPR_STR_ESC
} SWIFTY_STATE;

@implementation iTermSwiftyStringParser {
    SWIFTY_STATE _state;
}

- (instancetype)initWithString:(NSString *)string {
    self = [super init];
    if (self) {
        _string = [string copy];
        _state = SWIFTY_STATE_LITERAL;
    }
    return self;
}

- (NSInteger)enumerateSwiftySubstringsWithBlock:(void (^ _Nullable)(NSUInteger index,
                                                                    NSString *substring,
                                                                    BOOL isLiteral,
                                                                    BOOL *stop))block {
    int parens = 0;
    NSInteger start = 0;
    NSMutableArray<NSNumber *> *parensStack = [NSMutableArray array];
    NSUInteger index = 0;
    for (NSInteger i = 0; i < _string.length; i++) {
        unichar c = [_string characterAtIndex:i];
        switch (_state) {
            case SWIFTY_STATE_LITERAL:
                if (c == '\\') {
                    _state = SWIFTY_STATE_LITERAL_ESC;
                } else if (c == '"' && self.stopAtUnescapedQuote) {
                    if (block) {
                        BOOL stop = YES;
                        block(index, [_string substringWithRange:NSMakeRange(start, i - 1 - start)], YES, &stop);
                    }
                    return i;
                }
                break;

            case SWIFTY_STATE_LITERAL_ESC:
                if (c == '(') {
                    // Output range up to but not including \(
                    if (i - 1 - start >= 0) {
                        if (block) {
                            BOOL stop = NO;
                            block(index, [_string substringWithRange:NSMakeRange(start, i - 1 - start)], YES, &stop);
                            if (stop) {
                                return i;
                            }
                        }
                        index = i + 1;
                    }
                    start = i + 1;
                    parens = 1;
                    _state = SWIFTY_STATE_EXPR;
                } else {
                    _state = SWIFTY_STATE_LITERAL;
                }
                break;

            case SWIFTY_STATE_EXPR:
                if (c == '(') {
                    parens++;
                } else if (c == ')') {
                    parens--;
                    if (parens == 0) {
                        if (parensStack.count == 0) {
                            // Output range up to but not including )
                            if (i - start >= 0) {
                                if (block) {
                                    BOOL stop = NO;
                                    block(index, [_string substringWithRange:NSMakeRange(start, i - start)], NO, &stop);
                                    if (stop) {
                                        return i;
                                    }
                                }
                                index = i + 1;
                            }
                            // Next output begins after )
                            start = i + 1;
                            _state = SWIFTY_STATE_LITERAL;
                            break;  // do not output this paren. The opening \( was also not output.
                        } else {
                            // Ended a nested expression
                            parens = parensStack.lastObject.intValue;
                            [parensStack removeLastObject];
                            _state = SWIFTY_STATE_EXPR_STR;
                        }
                    }
                } else if (c == '"') {
                    _state = SWIFTY_STATE_EXPR_STR;
                }
                break;

            case SWIFTY_STATE_EXPR_STR:
                if (c == '\\') {
                    _state = SWIFTY_STATE_EXPR_STR_ESC;
                } else if (c == '"') {
                    _state = SWIFTY_STATE_EXPR;
                }
                break;

            case SWIFTY_STATE_EXPR_STR_ESC:
                if (c == '(') {
                    [parensStack addObject:@(parens)];
                    parens = 1;  // catch but don't output ) in expr state.
                    _state = SWIFTY_STATE_EXPR;
                } else {
                    _state = SWIFTY_STATE_EXPR_STR;
                }
                break;
        }
    }

    if (_string.length > start) {
        if (block) {
            BOOL ignore;
            block(index, [_string substringWithRange:NSMakeRange(start, _string.length - start)], YES, &ignore);
        }
    }
    if (self.stopAtUnescapedQuote) {
        if (self.tolerateTruncation) {
            _wasTruncated = YES;
            _wasTruncatedInLiteral = (_state == SWIFTY_STATE_LITERAL || _state == SWIFTY_STATE_LITERAL_ESC);
            return index;
        } else {
            return NSNotFound;
        }
    }
    if (_state == SWIFTY_STATE_EXPR ||
        _state == SWIFTY_STATE_EXPR_STR ||
        _state == SWIFTY_STATE_EXPR_STR_ESC) {
        if (self.tolerateTruncation) {
            _wasTruncated = YES;
            _wasTruncatedInLiteral = NO;
            return index;
        }
    }

    return _string.length;
}

@end
