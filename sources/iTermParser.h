//
//  iTermParser.h
//  iTerm2
//
//  Created by George Nachman on 1/5/15.
//
//  Utilities for parsing escape codes.

typedef struct {
    // Pointer to next character to read.
    unsigned char *datap;
    // Number of valid bytes starting at datap.
    int datalen;
    // Number of bytes already consumed. Subtract this from datap to get the original value of datap.
    int rmlen;
} iTermParserContext;

NS_INLINE iTermParserContext iTermParserContextMake(unsigned char *datap, int length) {
    iTermParserContext context = {
        .datap = datap,
        .datalen = length,
        .rmlen = 0
    };
    return context;
}

NS_INLINE BOOL iTermParserCanAdvance(iTermParserContext *context) {
    return context->datalen > 0;
}

NS_INLINE unsigned char iTermParserPeek(iTermParserContext *context) {
    return context->datap[0];
}

NS_INLINE void iTermParserAdvance(iTermParserContext *context) {
    context->datap++;
    context->datalen--;
    context->rmlen++;
}

NS_INLINE void iTermParserAdvanceMultiple(iTermParserContext *context, int n) {
    assert(context->datalen >= n);
    context->datap += n;
    context->datalen -= n;
    context->rmlen += n;
}

NS_INLINE BOOL iTermParserTryAdvance(iTermParserContext *context) {
    if (!iTermParserCanAdvance(context)) {
        return NO;
    }
    iTermParserAdvance(context);
    return YES;
}

NS_INLINE NSInteger iTermParserNumberOfBytesConsumed(iTermParserContext *context) {
    return context->rmlen;
}

// Only safe to call if iTermParserCanAdvance returns YES.
NS_INLINE unsigned char iTermParserConsume(iTermParserContext *context) {
    unsigned char c = context->datap[0];
    iTermParserAdvance(context);
    return c;
}

NS_INLINE BOOL iTermParserTryConsume(iTermParserContext *context, unsigned char *c) {
    if (!iTermParserCanAdvance(context)) {
        return NO;
    }
    *c = iTermParserConsume(context);
    return YES;
}

NS_INLINE void iTermParserConsumeOrDie(iTermParserContext *context, unsigned char expected) {
    unsigned char actual;
    BOOL consumedOk = iTermParserTryConsume(context, &actual);

    assert(consumedOk);
    assert(actual == expected);
}

NS_INLINE void iTermParserBacktrackBy(iTermParserContext *context, int n) {
    context->datap -= n;
    context->datalen += n;
    context->rmlen -= n;
}

NS_INLINE void iTermParserBacktrack(iTermParserContext *context) {
    iTermParserBacktrackBy(context, context->rmlen);
}

// Returns YES if any digits were found, NO if the first character was not a digit. |n| must be a
// valid pointer. It will be filled in with the integer at the start of the context and the context
// will be advanced to the end of the integer.
NS_INLINE BOOL iTermParserConsumeInteger(iTermParserContext *context, int *n) {
    int numDigits = 0;
    *n = 0;
    unsigned char c;
    while (iTermParserCanAdvance(context) &&
           isdigit((c = iTermParserPeek(context)))) {
        ++numDigits;
        *n *= 10;
        *n += (c - '0');
        iTermParserAdvance(context);
    }

    return numDigits > 0;
}
