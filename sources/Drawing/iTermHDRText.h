//
//  iTermHDRText.h
//  iTerm2
//
//  HDR text: the focused pane's text is drawn brighter than reference white on a
//  display with EDR headroom. These are the rules both renderers share, so they
//  agree on when to brighten text and by how much.
//

#import <Cocoa/Cocoa.h>

#import "NSColor+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

// Brightness is a linear multiple of reference white, like the HDR cursor. The
// default is the profile's KEY_HDR_TEXT_BRIGHTNESS default; the minimum and
// maximum bound the settings slider and the renderer.
extern const CGFloat iTermHDRTextDefaultBrightness;
extern const CGFloat iTermHDRTextMinimumBrightness;
extern const CGFloat iTermHDRTextMaximumBrightness;

// Brightens an sRGB-encoded text color (sRGB, extended sRGB, or Display P3
// components; above 1 is brighter than reference white) for HDR text. `gain`
// multiplies the light, so it is applied in linear light: 3 means three times
// as bright. If the brightest
// channel would go past `headroom` (linear), the whole color is scaled down
// together instead of clipping that channel, so the hue is kept. A gain of 1 or
// less returns the color unchanged. This is the CPU twin of iTermHDRBoostTextColor
// in iTermText.metal, which the legacy renderer uses so both renderers agree.
iTermSRGBColor iTermHDRTextBoostedColor(iTermSRGBColor encoded, CGFloat gain, CGFloat headroom);

// The linear brightness multiplier to draw this pane's text with, or 1.0 for no
// boost. Text is boosted only when the profile enables HDR text, the pane is the
// focused one (key window and active session), the default background is dark
// (on a light background a brighter foreground lowers contrast), and the display
// has EDR headroom. `requested` is the profile's KEY_HDR_TEXT_BRIGHTNESS;
// `headroom` is the screen's
// maximumPotentialExtendedDynamicRangeColorComponentValue, as for the HDR
// cursor. Each renderer also skips the boost per cell over a light cell
// background.
CGFloat iTermHDRTextGain(CGFloat requested,
                         BOOL profileEnabled,
                         BOOL focused,
                         NSColor *backgroundColor,
                         CGFloat headroom);

NS_ASSUME_NONNULL_END
