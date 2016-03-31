//
//  iTermTextViewAccessibilityHelper.h
//  iTerm2
//
//  Created by George Nachman on 6/22/15.
//
//

#import <Cocoa/Cocoa.h>
#import "ScreenChar.h"

// "Accessibility space" is the last lines of the session which are exposed to
// accessibility, as opposed to actual line numbers in the terminal. The 0th
// line in accessibility space may be the Nth line in the terminal, or the 0th
// line if accessibility space is at least as large as the terminal.
@protocol iTermTextViewAccessibilityHelperDelegate <NSObject>

// Return an array of characters for a line number in accessibility-space.
- (screen_char_t *)accessibilityHelperLineAtIndex:(int)accessibilityIndex;

// Return the width of the screen in cells.
- (int)accessibilityHelperWidth;

// Return the number of lines visible to accessibility.
- (int)accessibilityHelperNumberOfLines;

// Return the coordinate for a point in screen coords.
- (VT100GridCoord)accessibilityHelperCoordForPoint:(NSPoint)point;

// Return a rect in screen coords for a range of cells in accessibility-space.
- (NSRect)accessibilityHelperFrameForCoordRange:(VT100GridCoordRange)coordRange;

// Return the location of the cursor in accessibility-space.
- (VT100GridCoord)accessibilityHelperCursorCoord;

// Select the range, which is in accessibility-space.
- (void)accessibilityHelperSetSelectedRange:(VT100GridCoordRange)range;

// Gets the selected range in accessibility-space.
- (VT100GridCoordRange)accessibilityHelperSelectedRange;

// Returns the contents of selected text in accessibility-space only.
- (NSString *)accessibilityHelperSelectedText;

@end

// This outsources accessibilty methods for PTYTextView. It's useful to keep
// separate because it operates on a subset of the lines of the terminal and
// there's a clean interface here.
@interface iTermTextViewAccessibilityHelper : NSObject

@property(nonatomic, assign) id<iTermTextViewAccessibilityHelperDelegate> delegate;

- (NSArray *)accessibilityAttributeNames;
- (NSArray *)accessibilityParameterizedAttributeNames;
- (id)accessibilityAttributeValue:(NSString *)attribute forParameter:(id)parameter handled:(BOOL *)handled;
- (BOOL)accessibilityIsAttributeSettable:(NSString *)attribute handled:(BOOL *)handled;
- (void)accessibilitySetValue:(id)value forAttribute:(NSString *)attribute handled:(BOOL *)handled;
- (id)accessibilityAttributeValue:(NSString *)attribute handled:(BOOL *)handled;

@end
