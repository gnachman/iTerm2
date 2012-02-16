//
//  VT100Grid.h
//  iTerm
//
//  Created by George Nachman on 2/14/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "ScreenChar.h"
#include "LineBuffer.h"

typedef struct {
    int width;
    int height;
} GridSize;

typedef struct {
    int x;
    int y;
} GridPoint;

NS_INLINE GridPoint MakeGridPoint(int x, int y) {
    GridPoint g;
    g.x = x;
    g.y = y;
    return g;
}

NS_INLINE GridSize MakeGridSize(int width, int height) {
    GridSize s;
    s.width = width;
    s.height = height;
    return s;
}

@interface VT100Grid : NSObject {
    GridSize size_;
    NSMutableArray *lines_;
    GridPoint savedCursor_;
    GridPoint cursor_;
    LineBuffer *lineBuffer_;
    GridPoint selectionStart_;
    GridPoint selectionEnd_;  // non-inclusive
}

@property (nonatomic, readonly) GridSize size;
@property (nonatomic, assign) GridPoint savedCursor;
@property (nonatomic, assign) GridPoint cursor;
@property (nonatomic, retain) LineBuffer *lineBuffer;
@property (nonatomic, assign) GridPoint selectionStart;
@property (nonatomic, assign) GridPoint selectionEnd;

- (id)initWithSize:(GridSize)size defaultChar:(screen_char_t)defaultChar;
- (screen_char_t *)lineAtRow:(int)row;
- (void)setSize:(GridSize)size withDefaultChar:(screen_char_t)defaultChar;
- (int)usedHeight;
- (int)usedWidthOfLine:(screen_char_t *)theLine;

@end
