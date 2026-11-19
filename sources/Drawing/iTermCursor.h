#import <Cocoa/Cocoa.h>

#import "iTermSmartCursorColor.h"
#import "ScreenChar.h"

typedef NS_ENUM(NSInteger, ITermCursorType) {
    CURSOR_UNDERLINE,
    CURSOR_VERTICAL,
    CURSOR_BOX,

    CURSOR_DEFAULT = -1  // Use the default cursor type for a profile. Internally used for DECSTR.
};

@protocol iTermCursorDelegate <iTermSmartCursorColorDelegate>

- (void)cursorDrawCharacterAt:(VT100GridCoord)coord
                  doubleWidth:(BOOL)doubleWidth
                overrideColor:(NSColor*)overrideColor
                      context:(CGContextRef)ctx
              backgroundColor:(NSColor *)backgroundColor
                virtualOffset:(CGFloat)virtualOffset;

@end

// The maximum HDR cursor brightness, as a linear multiple of reference white (so
// 1.0 is no boost). These are the same units as NSScreen's EDR headroom. It is
// also the default for the profile's KEY_HDR_CURSOR_BRIGHTNESS, and is at least
// the potential headroom of current displays, so the default is as bright as the
// display allows. Shared by the legacy additive-boost path (iTermCursor) and the
// Metal cursor renderer so both request the same peak.
extern const CGFloat iTermHDRCursorMaximumBrightness;

// HDR text: the focused pane's text is drawn brighter than reference white on a
// display with EDR headroom. Brightness is a linear multiple of reference white,
// like the HDR cursor. The default is the profile's KEY_HDR_TEXT_BRIGHTNESS
// default; the minimum and maximum bound the settings slider and the renderer.
extern const CGFloat iTermHDRTextDefaultBrightness;
extern const CGFloat iTermHDRTextMinimumBrightness;
extern const CGFloat iTermHDRTextMaximumBrightness;

// An RGB color whose components are encoded with the sRGB transfer function
// (as in sRGB, extended sRGB, or Display P3). Values above 1 are brighter than
// reference white.
typedef struct {
    CGFloat red;
    CGFloat green;
    CGFloat blue;
} iTermHDRTextColor;

// Brightens an encoded text color for HDR text. `gain` multiplies the light, so it
// is applied in linear light: 3 means three times as bright. If the brightest
// channel would go past `headroom` (linear), the whole color is scaled down
// together instead of clipping that channel, so the hue is kept. A gain of 1 or
// less returns the color unchanged. This is the CPU twin of iTermHDRBoostTextColor
// in iTermText.metal, which the legacy renderer uses so both renderers agree.
iTermHDRTextColor iTermHDRTextBoostedColor(iTermHDRTextColor encoded, CGFloat gain, CGFloat headroom);

@interface iTermCursor : NSObject

@property (nonatomic, assign) id<iTermCursorDelegate> delegate;

// Multiplier in [0, 1] applied to the cursor's shadow opacity so it fades in
// step with the cursor during smooth blink. The cursor body itself is faded by
// the caller via CGContextSetAlpha around -drawWithRect:. Defaults to 1.
@property (nonatomic) CGFloat fadeAlpha;

// Target component value for a solid HDR cursor in the extended (gamma-encoded)
// color space, as returned by +hdrCursorComponentValueForRequestedBrightness:headroom:
// (so 1.0 means no boost). When greater than 1, the solid fill is pushed past
// white with additive passes so it renders as HDR on an EDR display. Defaults to 1.
@property (nonatomic) CGFloat hdrComponentValue;

+ (iTermCursor *)cursorOfType:(ITermCursorType)theType;
+ (instancetype)itermCopyModeCursorInSelectionState:(BOOL)selecting;

// No default implementation.
- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline
       virtualOffset:(CGFloat)virtualOffset;
- (void)drawShadow;
- (BOOL)isSolidRectangleWithFocused:(BOOL)focused;
- (NSRect)frameForSolidRectangle:(NSRect)rect;

@end

// Shared HDR-cursor logic used by both the Metal renderer and the legacy
// (drawRect:) drawing path so the two agree on when and how to brighten the
// cursor past reference white.
@interface iTermCursor (HDR)

// YES if the cursor should render as a bright HDR white instead of its normal
// appearance. The per-profile HDR-cursor setting is a hint: it only takes effect
// when the display has real headroom and the cursor sits on a dark background (a
// bright white cursor only makes sense there). Otherwise the caller draws a normal
// cursor, so cursor boost and smart cursor color still apply. `profileEnabled` is
// the profile's KEY_HDR_CURSOR value; `headroom` is the screen's
// maximumPotentialExtendedDynamicRangeColorComponentValue.
+ (BOOL)shouldUseHDRCursorOnBackground:(NSColor *)backgroundColor
                        profileEnabled:(BOOL)profileEnabled
                     potentialHeadroom:(CGFloat)headroom;

// Given that shouldUseHDRCursorOnBackground: returned YES, whether the cursor
// block is actually filled (and so should be forced to HDR white). This is the one
// cursor-type/focus exception on top of the type-agnostic predicate above: a box
// cursor in an unfocused window is drawn as a hollow frame that keeps its profile
// color, so it is NOT forced white; underline and vertical cursors are always
// filled. Defined once so the legacy and Metal paths cannot drift on this rule.
+ (BOOL)hdrCursorForcesWhiteForType:(ITermCursorType)type focused:(BOOL)focused;

// The color component value to draw an HDR cursor with. `requested` is the
// profile's KEY_HDR_CURSOR_BRIGHTNESS and `headroom` is what the display can
// take, both linear multiples of reference white. The cursor is drawn in an
// extended sRGB-curve color space (extended sRGB or Display P3), where a
// component value is gamma encoded: 2.0 is already about 5x white. So the
// clamped linear brightness is encoded with the sRGB transfer function. Both
// renderers use this so they agree on the peak.
+ (CGFloat)hdrCursorComponentValueForRequestedBrightness:(CGFloat)requested
                                                headroom:(CGFloat)headroom;

// The linear brightness multiplier to draw this pane's text with, or 1.0 for no
// boost. Text is boosted only when the profile enables HDR text, the pane is the
// focused one (key window and active session), the default background is dark
// (on a light background a brighter foreground lowers contrast), and the display
// has EDR headroom. `requested` is the profile's KEY_HDR_TEXT_BRIGHTNESS;
// `headroom` is the screen's
// maximumPotentialExtendedDynamicRangeColorComponentValue, as for the HDR
// cursor. Both renderers use this so they agree on when and how much to boost.
+ (CGFloat)hdrTextGainForRequestedBrightness:(CGFloat)requested
                              profileEnabled:(BOOL)profileEnabled
                                     focused:(BOOL)focused
                                  background:(NSColor *)backgroundColor
                           potentialHeadroom:(CGFloat)headroom;

@end
