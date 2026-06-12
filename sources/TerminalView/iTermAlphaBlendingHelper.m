//
//  iTermAlphaBlendingHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/24/20.
//

#import "iTermAlphaBlendingHelper.h"

// Threshold for preventing division by 0. 10^-3 is enough that the discontinuity is imperceptible.
const CGFloat iTermAlphaBlendingHelperEpsilon = 0.001;

// Formula for `q`
static CGFloat Q(CGFloat l) {
    assert(l < 1);
    assert(l >= 0);
    return 1.0 / (1.0 - l) - 1.0;
}

// Background color, aka b
CGFloat iTermAlphaValueForTopView(CGFloat t, CGFloat l) {
    if (l > (1 - iTermAlphaBlendingHelperEpsilon)) {
        // Problem (2)
        return 0;
    }

    // Formula for `b`
    const CGFloat alpha = (1.0 - t) / (Q(l) + 1);
    return alpha;
}

// Image, aka a
CGFloat iTermAlphaValueForBottomView(CGFloat t, CGFloat l) {
    if (l < iTermAlphaBlendingHelperEpsilon) {
        // Problem (3)
        return 0;
    }
    if (l > (1 - iTermAlphaBlendingHelperEpsilon)) {
        // Problem (1)
        return 1 - t;
    }
    const CGFloat q = Q(l);

    // Formula for `a`
    const CGFloat alpha = q * (1.0 - t) / (q + t);
    return alpha;
}
