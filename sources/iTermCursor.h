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
              backgroundColor:(NSColor *)backgroundColor;

@end

@interface iTermCursor : NSObject

@property(nonatomic, assign) id<iTermCursorDelegate> delegate;

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
             outline:(BOOL)outline;


@end
