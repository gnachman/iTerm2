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

NS_INLINE BOOL iTermParserTryPeek(iTermParserContext *context, unsigned char *c) {
    if (iTermParserCanAdvance(context)) {
        *c = iTermParserPeek(context);
        return YES;
    } else {
        return NO;
    }
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

NS_INLINE int iTermParserNumberOfBytesUntilCharacter(iTermParserContext *context, char c) {
    unsigned char *pointer = memchr(context->datap, '\n', context->datalen);
    if (!pointer) {
        return -1;
    } else {
        return pointer - context->datap;
    }
}

NS_INLINE int iTermParserLength(iTermParserContext *context) {
    return context->datalen;
}

NS_INLINE unsigned char *iTermParserPeekRawBytes(iTermParserContext *context, int length) {
    if (context->datalen < length) {
        return NULL;
    } else {
        return context->datap;
    }
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

#pragma mark - CSI

#define VT100CSIPARAM_MAX 16  // Maximum number of CSI parameters in VT100Token.csi->p.
#define VT100CSISUBPARAM_MAX 16  // Maximum number of CSI sub-parameters in VT100Token.csi->p.

typedef struct {
    // Integer parameters. The first |count| elements are valid. -1 means the value is unset; set
    // values are always nonnegative.
    int p[VT100CSIPARAM_MAX];

    // Number of defined values in |p|.
    int count;

    // An integer that holds a packed representation of the prefix byte, intermediate byte, and
    // final byte.
    int32_t cmd;

    // Sub-parameters.
    int sub[VT100CSIPARAM_MAX][VT100CSISUBPARAM_MAX];

    // Number of subparameters for each parameter.
    int subCount[VT100CSIPARAM_MAX];
} CSIParam;

// If the n'th parameter has a negative (default) value, replace it with |value|.
// CSI parameter values are all initialized to -1 before parsing, so this has the effect of setting
// a value iff it hasn't already been set.
// If there aren't yet n+1 parameters, increase the count to n+1.
NS_INLINE void iTermParserSetCSIParameterIfDefault(CSIParam *csiParam, int n, int value) {
    csiParam->p[n] = csiParam->p[n] < 0 ? value : csiParam->p[n];
    csiParam->count = MAX(csiParam->count, n + 1);
}
