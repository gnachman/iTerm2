//
//  iTermBackgroundColorRun.h
//  iTerm2
//
//  Created by George Nachman on 3/10/15.
//
//

#import <Cocoa/Cocoa.h>
#import "ScreenChar.h"

@class iTermBoxedBackgroundColorRun;
@class iTermTextExtractor;

typedef struct {
    NSRange range;
    int bgColor;
    int bgGreen;
    int bgBlue;
    ColorMode bgColorMode;
    BOOL selected;
    BOOL isMatch;
    // Because subpixel AA only works with "atop" blending, we have to blend fg & bg before drawing.
    // Although I would rather draw an fg with 50% alpha, that won't look good with subpixel AA.
    // This introduces a per-cell dependency between fg & bg. In order to not lose the optimization
    // where we only use unprocessed colors, track this so we don't merge background runs when faint
    // text is present.
    BOOL beneathFaintText;
} iTermBackgroundColorRun;

// NOTE: This does not compare the ranges.
NS_INLINE BOOL iTermBackgroundColorRunsEqual(iTermBackgroundColorRun *a,
                                             iTermBackgroundColorRun *b) {
    return (a->bgColor == b->bgColor &&
            a->bgGreen == b->bgGreen &&
            a->bgBlue == b->bgBlue &&
            a->bgColorMode == b->bgColorMode &&
            a->selected == b->selected &&
            a->isMatch == b->isMatch &&
            a->beneathFaintText == b->beneathFaintText);
}

// A collection of color runs for a single line, along with info about the line itself.
@interface iTermBackgroundColorRunsInLine : NSObject

// y coordinate to draw at
@property(nonatomic, assign) CGFloat y;

// Line number to draw at (row - scrollbackOverflow)
@property(nonatomic, assign) int line;
// Line number the values came from. Usually the same as `line` except for
// offscreen command lines.
@property(nonatomic, assign) int sourceLine;

@property(nonatomic, retain) NSArray<iTermBoxedBackgroundColorRun *> *array;
@property(nonatomic, assign) NSInteger numberOfEquivalentRows;

// Creates a new autoreleased iTermBackgroundColorRunsInLine object that's ready to use.
// Fills in *anyBlinkPtr with YES if some character in the range is blinking.
+ (instancetype)backgroundRunsInLine:(const screen_char_t *)theLine
                          lineLength:(int)width
                    sourceLineNumber:(int)sourceLineNumber
                   displayLineNumber:(int)displayLineNumber
                     selectedIndexes:(NSIndexSet *)selectedIndexes
                         withinRange:(NSRange)charRange
                             matches:(NSData *)matches
                            anyBlink:(BOOL *)anyBlinkPtr
                                   y:(CGFloat)y;  // Value for self.y

+ (instancetype)defaultRunOfLength:(int)width
                               row:(int)row
                                 y:(CGFloat)y;

- (iTermBackgroundColorRun *)runAtIndex:(int)i;
- (iTermBackgroundColorRun *)lastRun;

@end

// An NSObject wrapper for a color run with an optional NSColor.
@interface iTermBoxedBackgroundColorRun : NSObject
@property(nonatomic, readonly) iTermBackgroundColorRun *valuePointer;
@property(nonatomic, retain) NSColor *backgroundColor;
@property(nonatomic, retain) NSColor *unprocessedBackgroundColor;

+ (instancetype)boxedBackgroundColorRunWithValue:(iTermBackgroundColorRun)value;

@end

