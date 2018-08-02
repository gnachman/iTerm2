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

@interface iTermUnderlineCursor : iTermCursor
@end

@interface iTermVerticalCursor : iTermCursor
@end

@interface iTermBoxCursor : iTermCursor
@end

@interface iTermCopyModeCursor : iTermCursor
@property (nonatomic) BOOL selecting;
@end

@implementation iTermCursor

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
             outline:(BOOL)outline {
}

- (void)drawOutlineOfRect:(NSRect)cursorRect withColor:(NSColor *)color {
    [[color colorWithAlphaComponent:0.75] set];
    NSRect rect = cursorRect;
    CGFloat frameWidth = 0.5;
    rect.origin.x -= frameWidth;
    rect.origin.y -= frameWidth;
    rect.size.width += frameWidth * 2;
    rect.size.height += frameWidth * 2;
    NSFrameRectWithWidthUsingOperation(rect, 0.5, NSCompositingOperationSourceOver);
}

@end

@implementation iTermUnderlineCursor

- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline {
    const CGFloat height = [iTermAdvancedSettingsModel underlineCursorHeight];
    NSRect cursorRect = NSMakeRect(rect.origin.x,
                                   rect.origin.y + rect.size.height - height - [iTermAdvancedSettingsModel underlineCursorOffset],
                                   ceil(rect.size.width),
                                   height);
    if (outline) {
        [self drawOutlineOfRect:cursorRect withColor:backgroundColor];
    } else {
        [backgroundColor set];
        NSRectFill(cursorRect);
    }
}

@end

@implementation iTermVerticalCursor

- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline {
    NSRect cursorRect = NSMakeRect(rect.origin.x, rect.origin.y, [iTermAdvancedSettingsModel verticalBarCursorWidth], rect.size.height);
    if (outline) {
        [self drawOutlineOfRect:cursorRect withColor:backgroundColor];
    } else {
        [backgroundColor set];
        NSRectFill(cursorRect);
    }
}

@end

@implementation iTermCopyModeCursor

- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline {
    const CGFloat heightFraction = 1 / 3.0;
    NSRect cursorRect = NSMakeRect(rect.origin.x - rect.size.width,
                                   rect.origin.y,
                                   rect.size.width * 2,
                                   rect.size.height * heightFraction);

    const CGFloat r = self.selecting ? 2 : 1;
    NSBezierPath *path;
    path = [[[NSBezierPath alloc] init] autorelease];
    [path moveToPoint:NSMakePoint(NSMinX(cursorRect), NSMinY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) - r, NSMaxY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) - r, NSMaxY(rect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) + r, NSMaxY(rect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) + r, NSMaxY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMaxX(cursorRect), NSMinY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMinX(cursorRect), NSMinY(cursorRect))];
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

- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline {
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
        NSFrameRect(rect);
        return;
    } else {
        NSRectFill(rect);
    }

    if (screenChar.code) {
        // Draw the character over the cursor.
        CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
        if (smart && focused) {
            [self drawSmartCursorCharacter:screenChar
                               doubleWidth:doubleWidth
                           backgroundColor:backgroundColor
                                       ctx:ctx
                                     coord:coord];
        } else {
            // Non-smart
            [self.delegate cursorDrawCharacterAt:coord
                                     doubleWidth:doubleWidth
                                   overrideColor:foregroundColor
                                         context:ctx
                                 backgroundColor:backgroundColor];
        }
    }
}

- (void)drawSmartCursorCharacter:(screen_char_t)screenChar
                     doubleWidth:(BOOL)doubleWidth
                 backgroundColor:(NSColor *)backgroundColor
                             ctx:(CGContextRef)ctx
                           coord:(VT100GridCoord)coord {
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
                         backgroundColor:nil];

}

@end
