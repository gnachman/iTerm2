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

@interface iTermCursor : NSObject

@property (nonatomic, assign) id<iTermCursorDelegate> delegate;

// Multiplier in [0, 1] applied to the cursor's shadow opacity so it fades in
// step with the cursor during smooth blink. The cursor body itself is faded by
// the caller via CGContextSetAlpha around -drawWithRect:. Defaults to 1.
@property (nonatomic) CGFloat fadeAlpha;

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
