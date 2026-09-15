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

// The maximum HDR cursor brightness, in units of reference white (so 1.0 is no
// boost). Shared by the legacy additive-boost path (iTermCursor) and the Metal
// cursor renderer so both request the same peak regardless of the display's
// potential headroom, which would otherwise make the cursor change brightness
// when the GPU renderer is toggled. The display tonemaps this down to what it can
// actually show.
extern const CGFloat iTermHDRCursorMaximumBrightness;

@interface iTermCursor : NSObject

@property (nonatomic, assign) id<iTermCursorDelegate> delegate;

// Multiplier in [0, 1] applied to the cursor's shadow opacity so it fades in
// step with the cursor during smooth blink. The cursor body itself is faded by
// the caller via CGContextSetAlpha around -drawWithRect:. Defaults to 1.
@property (nonatomic) CGFloat fadeAlpha;

// Target brightness for a solid HDR cursor, in units of reference white (so 1.0
// means no boost). When greater than 1, the solid fill is pushed past white with
// additive passes so it renders as HDR on an EDR display. Defaults to 1.
@property (nonatomic) CGFloat hdrBrightness;

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

@end
