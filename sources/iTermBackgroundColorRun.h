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
} iTermBackgroundColorRun;

// NOTE: This does not compare the ranges.
NS_INLINE BOOL iTermBackgroundColorRunsEqual(iTermBackgroundColorRun *a,
                                             iTermBackgroundColorRun *b) {
    return (a->bgColor == b->bgColor &&
            a->bgGreen == b->bgGreen &&
            a->bgBlue == b->bgBlue &&
            a->bgColorMode == b->bgColorMode &&
            a->selected == b->selected &&
            a->isMatch == b->isMatch);
}

// A collection of color runs for a single line, along with info about the line itself.
@interface iTermBackgroundColorRunsInLine : NSObject

// y coordinate to draw at
@property(nonatomic, assign) CGFloat y;

// Line number to draw at (row - scrollbackOverflow)
@property(nonatomic, assign) int line;

@property(nonatomic, retain) NSArray<iTermBoxedBackgroundColorRun *> *array;

// Creates a new autoreleased iTermBackgroundColorRunsInLine object that's ready to use.
// Fills in *anyBlinkPtr with YES if some character in the range is blinking.
+ (instancetype)backgroundRunsInLine:(screen_char_t *)theLine
                          lineLength:(int)width
                                 row:(int)row  // Row number in datasource
                     selectedIndexes:(NSIndexSet *)selectedIndexes
                         withinRange:(NSRange)charRange
                             matches:(NSData *)matches
                            anyBlink:(BOOL *)anyBlinkPtr
                       textExtractor:(iTermTextExtractor *)extractor
                                   y:(CGFloat)y  // Value for self.y
                                line:(int)line;  // Value for self.line

@end

// An NSObject wrapper for a color run with an optional NSColor.
@interface iTermBoxedBackgroundColorRun : NSObject
@property(nonatomic, readonly) iTermBackgroundColorRun *valuePointer;
@property(nonatomic, retain) NSColor *backgroundColor;
@property(nonatomic, retain) NSColor *unprocessedBackgroundColor;
@end

