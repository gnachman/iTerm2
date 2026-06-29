//
//  iTermSquash.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/28/20.
//

#import "iTermSquash.h"

#import <math.h>

// We want to keep the offset from getting too far from the limit (be it negative values
// below zero or positive values past the maximum allowable offset). Let's use negative
// values as an example. When the raw offset goes just slightly negative, we'd like the
// effective offset to be approximately equal. As the raw offset becomes farther from
// zero, the effective offset should start to change more slowly. And no matter how far
// from zero the raw offset is, the effective offset can never exceed -limit.
//
// In other words, we want a function f(rawOffset) with the following properties:
// 1. Monotonically decreasing
// 2. Asymptotic on -limit
// 3. f'(0)=1
// 4. Smooth
//
// This function is asymptotic on l starting at 0 at x=0. We'll only consider x>=0.
//   ĝ(x) = l * (1 - e^(-x))
// The base e is arbitrary and doesn't give g'(0)=1. Let's call the base b and find a value
// of b that gives g'(0)=1.
//   g(x) = l * (1 - b^(-x))
// A bit of the old wolfram alpha gives:
//   dg/dx = l*b^(-x)*log(b) = g'(x)
// Which at x=0 is simply:
//   g'(0) = l * log(b)
// We want g'(0)=1:
//   1 = l * log(b)
// Solve for b:
//   b = e^(1/l)
// Plug this back in to g:
//   g(x) = l * (1 - b^(-x))
//
// The final results are:
//   f(x) = -g(-x)          (for x < 0)
//   f(x) = x               (for x in [0,m])
//   f(x) = m + g(x - m)    (for x > m)
CGFloat iTermSquash(CGFloat x, CGFloat upperBound, CGFloat maxWiggle) {
    const CGFloat l = maxWiggle;
    const CGFloat m = upperBound;
    const CGFloat b = exp(1.0 / l);
    CGFloat (^g)(CGFloat) = ^CGFloat(CGFloat x) {
        return l * (1.0 - pow(b, -x));
    };
    if (x < 0) {
        return -g(-x);
    }
    if (x <= m) {
        return x;
    }
    return m + g(x - m);
}

