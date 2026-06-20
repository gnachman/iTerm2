//
//  iTermStatusBarView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermTuple.h"

@interface iTermStatusBarView : NSView

// color, x offset
@property (nonatomic, copy) NSArray<NSNumber *> *separatorOffsets;
@property (nonatomic, copy) NSArray<iTermTuple<NSColor *, NSNumber *> *> *backgroundColors;
@property (nonatomic) NSColor *separatorColor;
@property (nonatomic) NSColor *backgroundColor;
@property (nonatomic) CGFloat verticalOffset;

// When YES, draws a 1pt separator line along the edge of the status bar that
// abuts the terminal content (bottom edge when the status bar is on top, top
// edge when it is on the bottom). The line is drawn inside the existing bounds
// so it does not increase the status bar's height.
@property (nonatomic) BOOL drawsSeparatorBetweenStatusBarAndTerminal;

// Color of the edge separator. When nil, the system separator color is used
// (matching the workgroup toolbar in non-minimal themes).
@property (nonatomic, nullable) NSColor *edgeSeparatorColor;

@end
