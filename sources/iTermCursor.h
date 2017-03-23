#import <Cocoa/Cocoa.h>
#import "ScreenChar.h"

typedef NS_ENUM(NSInteger, ITermCursorType) {
    CURSOR_UNDERLINE,
    CURSOR_VERTICAL,
    CURSOR_BOX,

    CURSOR_DEFAULT = -1  // Use the default cursor type for a profile. Internally used for DECSTR.
};

typedef struct {
    screen_char_t chars[3][3];
    BOOL valid[3][3];
} iTermCursorNeighbors;

@protocol iTermCursorDelegate <NSObject>

- (iTermCursorNeighbors)cursorNeighbors;

- (void)cursorDrawCharacterAt:(VT100GridCoord)coord
                overrideColor:(NSColor*)overrideColor
                      context:(CGContextRef)ctx
              backgroundColor:(NSColor *)backgroundColor;

- (NSColor *)cursorColorForCharacter:(screen_char_t)screenChar
                      wantBackground:(BOOL)wantBackgroundColor
                               muted:(BOOL)muted;

- (NSColor *)cursorWhiteColor;
- (NSColor *)cursorBlackColor;
- (NSColor *)cursorColorByDimmingSmartColor:(NSColor *)color;

@end

@interface iTermCursor : NSObject

@property(nonatomic, assign) id<iTermCursorDelegate> delegate;

+ (iTermCursor *)cursorOfType:(ITermCursorType)theType;

// No default implementation.
- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline;


@end
