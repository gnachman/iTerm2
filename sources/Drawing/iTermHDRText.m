//
//  iTermHDRText.m
//  iTerm2
//

#import "iTermHDRText.h"

const CGFloat iTermHDRTextDefaultBrightness = 3.0;
const CGFloat iTermHDRTextMinimumBrightness = 1.5;
const CGFloat iTermHDRTextMaximumBrightness = 16.0;

CGFloat iTermHDRTextGain(CGFloat requested,
                         BOOL profileEnabled,
                         BOOL focused,
                         NSColor *backgroundColor,
                         CGFloat headroom) {
    if (!profileEnabled || !focused || headroom <= 1) {
        return 1.0;
    }
    // Brightening the foreground only adds contrast over a dark background.
    if (!backgroundColor.isDark) {
        return 1.0;
    }
    return MAX(1.0, MIN(MIN(requested, headroom), iTermHDRTextMaximumBrightness));
}

iTermSRGBColor iTermHDRTextBoostedColor(iTermSRGBColor encoded, CGFloat gain, CGFloat headroom) {
    if (!(gain > 1)) {
        return encoded;
    }
    // Like the shader, negative components are treated as 0.
    const iTermRGBColor linear = iTermLinearizeSRGB((iTermSRGBColor){
        .r = MAX(encoded.r, 0),
        .g = MAX(encoded.g, 0),
        .b = MAX(encoded.b, 0)
    });
    const CGFloat peak = MAX(linear.r, MAX(linear.g, linear.b));
    CGFloat effectiveGain = gain;
    if (peak > 0) {
        effectiveGain = MIN(gain, MAX(1.0, MAX(headroom, 1.0) / peak));
    }
    return iTermCompressRGB((iTermRGBColor){
        .r = linear.r * effectiveGain,
        .g = linear.g * effectiveGain,
        .b = linear.b * effectiveGain
    });
}
