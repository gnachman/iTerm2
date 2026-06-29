//
//  VT100StringConversionConfig.h
//  iTerm2
//
//  Created by George Nachman on 3/22/26.
//

#import "iTermUnicodeNormalization.h"

// Configuration snapshot pushed from the mutation thread to the parser thread
// for pre-converting non-ASCII strings to screen_char_t arrays.
typedef struct {
    BOOL ambiguousIsDoubleWidth;
    iTermUnicodeNormalization normalization;
    NSInteger unicodeVersion;
    BOOL softAlternateScreenMode;
} VT100StringConversionConfig;

// Field-by-field comparison (memcmp is unsafe due to struct padding).
NS_INLINE BOOL VT100StringConversionConfigEquals(const VT100StringConversionConfig *a,
                                                  const VT100StringConversionConfig *b) {
    return (a->ambiguousIsDoubleWidth == b->ambiguousIsDoubleWidth &&
            a->normalization == b->normalization &&
            a->unicodeVersion == b->unicodeVersion &&
            a->softAlternateScreenMode == b->softAlternateScreenMode);
}
