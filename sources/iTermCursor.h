#import <Cocoa/Cocoa.h>

#import "iTermCursorType.h"
#import "iTermSmartCursorColor.h"
#import "ScreenChar.h"

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
+ (instancetype)copyModeCursorInSelectionState:(BOOL)selecting;

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
