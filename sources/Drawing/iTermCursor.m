//
//  iTermCursor.m
//  iTerm2
//
//  Created by George Nachman on 3/13/15.
//
//

#import "iTermCursor.h"
#import "DebugLogging.h"
#import "NSColor+iTerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermSmartCursorColor.h"
#import "iTermVirtualOffset.h"

@interface iTermUnderlineCursor : iTermCursor
@end

@interface iTermVerticalCursor : iTermCursor
@end

@interface iTermBoxCursor : iTermCursor
@end

@interface iTermCopyModeCursor : iTermCursor
@property (nonatomic) BOOL selecting;
@end

@implementation iTermCursor {
    BOOL _shouldDrawShadow;
    NSRect _shadowRect;
    BOOL _dark;
    CGFloat _virtualOffset;
}

+ (iTermCursor *)cursorOfType:(ITermCursorType)theType {
    switch (theType) {
        case CURSOR_UNDERLINE:
            return [[[iTermUnderlineCursor alloc] init] autorelease];

        case CURSOR_VERTICAL:
            return [[[iTermVerticalCursor alloc] init] autorelease];

        case CURSOR_BOX:
            return [[[iTermBoxCursor alloc] init] autorelease];

        default:
            return nil;
    }
}

+ (instancetype)itermCopyModeCursorInSelectionState:(BOOL)selecting {
    iTermCopyModeCursor *cursor = [[[iTermCopyModeCursor alloc] init] autorelease];
    cursor.selecting = selecting;
    return cursor;
}

- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline
       virtualOffset:(CGFloat)virtualOffset {
}

- (BOOL)isSolidRectangleWithFocused:(BOOL)focused {
    return YES;
}

- (NSRect)frameForSolidRectangle:(NSRect)rect {
    return rect;
}

- (void)drawOutlineOfRect:(NSRect)cursorRect withColor:(NSColor *)color virtualOffset:(CGFloat)virtualOffset {
    [[color colorWithAlphaComponent:0.75] set];
    NSRect rect = cursorRect;
    CGFloat frameWidth = 0.5;
    rect.origin.x -= frameWidth;
    rect.origin.y -= frameWidth;
    rect.size.width += frameWidth * 2;
    rect.size.height += frameWidth * 2;
    iTermFrameRectWithWidthUsingOperation(rect, 0.5, NSCompositingOperationSourceOver, virtualOffset);
}

- (void)setShadowOverDarkBackground:(BOOL)dark rect:(NSRect)rect virtualOffset:(CGFloat)virtualOffset {
    _shouldDrawShadow = YES;
    _dark = dark;
    _shadowRect = rect;
    _virtualOffset = virtualOffset;
}

- (void)drawShadow {
    if (!_shouldDrawShadow) {
        return;
    }
    NSColor *shadowColor;
    if (_dark) {
        shadowColor = [NSColor colorWithWhite:1 alpha:0.5];
    } else {
        shadowColor = [NSColor colorWithWhite:0 alpha:0.5];
    }
    [shadowColor set];
    iTermRectFillUsingOperation(_shadowRect, NSCompositingOperationSourceOver, _virtualOffset);
}

@end

@implementation iTermUnderlineCursor

- (NSRect)frameForSolidRectangle:(NSRect)rect {
    const CGFloat height = [iTermAdvancedSettingsModel underlineCursorHeight];
    NSRect cursorRect = NSMakeRect(rect.origin.x,
                                   rect.origin.y + rect.size.height - height - [iTermAdvancedSettingsModel underlineCursorOffset],
                                   ceil(rect.size.width),
                                   height);
    return cursorRect;
}

- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline
       virtualOffset:(CGFloat)virtualOffset {
    NSRect cursorRect = [self frameForSolidRectangle:rect];
    if (outline) {
        [self drawOutlineOfRect:cursorRect
                      withColor:backgroundColor
                  virtualOffset:virtualOffset];
    } else {
        [backgroundColor set];
        iTermRectFill(cursorRect, virtualOffset);
        NSRect shadowRect = cursorRect;
        shadowRect.origin.y -= 1;
        shadowRect.size.height = 1;
        [self setShadowOverDarkBackground:backgroundColor.isDark
                                     rect:shadowRect
                            virtualOffset:virtualOffset];
    }
}

@end

@implementation iTermVerticalCursor

- (NSRect)frameForSolidRectangle:(NSRect)rect {
    return NSMakeRect(rect.origin.x, rect.origin.y, [iTermAdvancedSettingsModel verticalBarCursorWidth], rect.size.height);

}

- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline
       virtualOffset:(CGFloat)virtualOffset {
    NSRect cursorRect = [self frameForSolidRectangle:rect];
    if (outline) {
        [self drawOutlineOfRect:cursorRect withColor:backgroundColor virtualOffset:virtualOffset];
    } else {
        [backgroundColor set];
        iTermRectFill(cursorRect, virtualOffset);
        NSRect shadowRect = cursorRect;
        shadowRect.origin.x += NSWidth(shadowRect);
        shadowRect.size.width = 1;
        [self setShadowOverDarkBackground:backgroundColor.isDark rect:shadowRect virtualOffset:virtualOffset];
    }
}

@end

@implementation iTermCopyModeCursor

- (BOOL)isSolidRectangle {
    return NO;
}

- (NSRect)frameForSolidRectangle:(NSRect)rect {
    return NSZeroRect;
}

- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline
       virtualOffset:(CGFloat)virtualOffset {
    const CGFloat heightFraction = 1 / 3.0;
    NSRect cursorRect = NSMakeRect(rect.origin.x - rect.size.width,
                                   rect.origin.y,
                                   rect.size.width * 2,
                                   rect.size.height * heightFraction);

    const CGFloat r = self.selecting ? 2 : 1;
    NSBezierPath *path;
    path = [[[NSBezierPath alloc] init] autorelease];
    [path it_moveToPoint:NSMakePoint(NSMinX(cursorRect), NSMinY(cursorRect)) virtualOffset:virtualOffset];
    [path it_lineToPoint:NSMakePoint(NSMidX(cursorRect) - r, NSMaxY(cursorRect)) virtualOffset:virtualOffset];
    [path it_lineToPoint:NSMakePoint(NSMidX(cursorRect) - r, NSMaxY(rect)) virtualOffset:virtualOffset];
    [path it_lineToPoint:NSMakePoint(NSMidX(cursorRect) + r, NSMaxY(rect)) virtualOffset:virtualOffset];
    [path it_lineToPoint:NSMakePoint(NSMidX(cursorRect) + r, NSMaxY(cursorRect)) virtualOffset:virtualOffset];
    [path it_lineToPoint:NSMakePoint(NSMaxX(cursorRect), NSMinY(cursorRect)) virtualOffset:virtualOffset];
    [path it_lineToPoint:NSMakePoint(NSMinX(cursorRect), NSMinY(cursorRect)) virtualOffset:virtualOffset];
    if (self.selecting) {
        [[NSColor colorWithRed:0xc1 / 255.0 green:0xde / 255.0 blue:0xff / 255.0 alpha:1] set];
    } else {
        [[NSColor whiteColor] set];
    }
    [path fill];

    [[NSColor blackColor] set];
    [path stroke];
}

@end

@implementation iTermBoxCursor {
    iTermSmartCursorColor *_smartCursorColor;
}

- (void)dealloc {
    [_smartCursorColor release];
    [super dealloc];
}

- (BOOL)isSolidRectangleWithFocused:(BOOL)focused {
    return focused;
}

- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline
       virtualOffset:(CGFloat)virtualOffset {
    assert(!outline);

    // Draw the colored box/frame
    if (smart) {
        if (_smartCursorColor == nil) {
            _smartCursorColor = [[iTermSmartCursorColor alloc] init];
        }
        _smartCursorColor.delegate = self.delegate;
        backgroundColor = [_smartCursorColor backgroundColorForCharacter:screenChar];
    }
    [backgroundColor set];
    const BOOL frameOnly = !focused;
    if (frameOnly) {
        iTermFrameRect(rect, virtualOffset);
        return;
    } else {
        iTermRectFill(rect, virtualOffset);
    }

    if (screenChar.code) {
        // Draw the character over the cursor.
        CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] CGContext];
        if (smart && focused) {
            [self drawSmartCursorCharacter:screenChar
                               doubleWidth:doubleWidth
                           backgroundColor:backgroundColor
                                       ctx:ctx
                                     coord:coord
                             virtualOffset:virtualOffset];
        } else {
            // Non-smart
            [self.delegate cursorDrawCharacterAt:coord
                                     doubleWidth:doubleWidth
                                   overrideColor:foregroundColor
                                         context:ctx
                                 backgroundColor:backgroundColor
                                   virtualOffset:virtualOffset];
        }
    }
}

- (void)drawSmartCursorCharacter:(screen_char_t)screenChar
                     doubleWidth:(BOOL)doubleWidth
                 backgroundColor:(NSColor *)backgroundColor
                             ctx:(CGContextRef)ctx
                           coord:(VT100GridCoord)coord
                   virtualOffset:(CGFloat)virtualOffset {
    NSColor *regularTextColor = [self.delegate cursorColorForCharacter:screenChar
                                                        wantBackground:YES
                                                                 muted:NO];
    NSColor *overrideColor = [_smartCursorColor textColorForCharacter:screenChar
                                                     regularTextColor:regularTextColor
                                                 smartBackgroundColor:backgroundColor];
    [self.delegate cursorDrawCharacterAt:coord
                             doubleWidth:doubleWidth
                           overrideColor:overrideColor
                                 context:ctx
                         backgroundColor:nil
                           virtualOffset:virtualOffset];

}

@end
