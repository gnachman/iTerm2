#import <Cocoa/Cocoa.h>
#import "ScreenChar.h"

typedef enum {
    CURSOR_UNDERLINE,
    CURSOR_VERTICAL,
    CURSOR_BOX,

    CURSOR_DEFAULT = -1  // Use the default cursor type for a profile. Internally used for DECSTR.
} ITermCursorType;

typedef struct {
    screen_char_t chars[3][3];
    BOOL valid[3][3];
} iTermCursorNeighbors;

@protocol iTermCursorDelegate <NSObject>

- (iTermCursorNeighbors)cursorNeighbors;

- (void)cursorDrawCharacter:(screen_char_t)screenChar
                        row:(int)row
                      point:(NSPoint)point
                doubleWidth:(BOOL)doubleWidth
              overrideColor:(NSColor*)overrideColor
                    context:(CGContextRef)ctx
            backgroundColor:(NSColor *)backgroundColor;

- (NSColor *)cursorColorForCharacter:(screen_char_t)screenChar
                      wantBackground:(BOOL)wantBackgroundColor
                               muted:(BOOL)muted;

- (NSColor *)cursorWhiteColor;
- (NSColor *)cursorBlackColor;

@end

@interface iTermCursor : NSObject

@property(nonatomic, assign) id<iTermCursorDelegate> delegate;

+ (iTermCursor *)cursorOfType:(ITermCursorType)theType;

// No default implementation.
- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
          cellHeight:(CGFloat)cellHeight;


@end
