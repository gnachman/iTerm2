//
//  iTermBackgroundColorRun.h
//  iTerm2
//
//  Created by George Nachman on 3/10/15.
//
//

#import <Cocoa/Cocoa.h>
#import "ScreenChar.h"

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
@property(nonatomic, assign) CGFloat y;
@property(nonatomic, assign) int line;
@property(nonatomic, retain) NSArray *array;
@end

// An NSObject wrapper for a color run with an optional NSColor.
@interface iTermBoxedBackgroundColorRun : NSObject
@property(nonatomic, readonly) iTermBackgroundColorRun *valuePointer;
@property(nonatomic, retain) NSColor *backgroundColor;
@end

