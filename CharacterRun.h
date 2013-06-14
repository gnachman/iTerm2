//
//  CharacterRun.h
//  iTerm
//
//  Created by George Nachman on 12/16/12.
//
//

#import <Cocoa/Cocoa.h>
#import "PTYFontInfo.h"
#import <ApplicationServices/ApplicationServices.h>

#define kCharacterRunTempSize 100


// When drawing lines, we use this object represents a run of cells of
// the same font and attributes, differing only in the characters displayed.
@interface CharacterRun : NSObject <NSCopying> {
    BOOL antiAlias_;
    NSColor *color_;
    BOOL fakeBold_;
    CGFloat x_;
    PTYFontInfo *fontInfo_;
	// Aggregates codes from appendCode:withAdvance: because appending to an attributed string is slow.
    unichar temp_[kCharacterRunTempSize];
    int tempCount_;
    NSMutableAttributedString *string_;

	// Array of advances. Gets realloced. If there are multiple characters in a cell, the first will
    // have a positive advance and the others will have a 0 advance. Core Text's positions are used
    // for those codes.
    float *advances_;
    int advancesSize_;  // used space
    int advancesCapacity_;  // available space

    BOOL advancedFontRendering_;
}

@property (nonatomic, assign) BOOL antiAlias;           // Use anti-aliasing?
@property (nonatomic, retain) NSColor *color;           // Foreground color
@property (nonatomic, assign) BOOL fakeBold;            // Should bold text be rendered by drawing text twice with a 1px shift?
@property (nonatomic, assign) CGFloat x;                // x pixel coordinate for the run's start.
@property (nonatomic, retain) PTYFontInfo *fontInfo;    // Font to use.
@property (nonatomic, assign) BOOL advancedFontRendering;

// Returns YES if the codes in otherRun can be safely added to this run.
- (BOOL)isCompatibleWith:(CharacterRun *)otherRun;

// Append codes from |string|, which will be rendered in a single cell (perhaps double-width) and may
// include combining marks.
- (void)appendCodesFromString:(NSString *)string withAdvance:(CGFloat)advance;

// This adds the code to temporary storage; call |commit| to actually append.
- (void)appendCode:(unichar)code withAdvance:(CGFloat)advance;

// Returns a newly allocated line.
- (CTLineRef)newLine;

// Commit appended codes to the internal string.
- (void)commit;

// Returns the positions for characters in the given run, which begins at the specified character
// and x position. Returns the number of characters.
- (int)getPositions:(NSPoint *)positions
             forRun:(CTRunRef)run
    startingAtIndex:(int)firstCharacterIndex
         glyphCount:(int)glyphCount
        runWidthPtr:(CGFloat *)runWidthPtr;

@end
