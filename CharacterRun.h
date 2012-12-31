//
//  CharacterRun.h
//  iTerm
//
//  Created by George Nachman on 12/16/12.
//
//

#import <Cocoa/Cocoa.h>
#import "PTYFontInfo.h"
#import "SharedCharacterRunData.h"

typedef enum {
    kCharacterRunMultipleSimpleChars,           // A run of cells with one code point each.
    kCharacterRunSingleCharWithCombiningMarks   // A single cell with multiple code points.
} RunType;

// When drawing lines, we use this object represents a run of cells of
// the same font and attributes, differing only in the characters displayed.
@interface CharacterRun : NSObject <NSCopying> {
    BOOL antiAlias_;
    NSColor *color_;
    RunType runType_;
    BOOL fakeBold_;
    CGFloat x_;
    PTYFontInfo *fontInfo_;
    SharedCharacterRunData *sharedData_;
    NSRange range_;
}

@property (nonatomic, assign) BOOL antiAlias;           // Use anti-aliasing?
@property (nonatomic, retain) NSColor *color;           // Foreground color
@property (nonatomic, assign) RunType runType;          // Type of run
@property (nonatomic, assign) BOOL fakeBold;            // Should bold text be rendered by drawing text twice with a 1px shift?
@property (nonatomic, assign) CGFloat x;                // x pixel coordinate for the run's start.
@property (nonatomic, retain) PTYFontInfo *fontInfo;    // Font to use.
@property (nonatomic, retain) SharedCharacterRunData *sharedData;
@property (nonatomic, assign) NSRange range;            // Range this run uses in shared data.

// Divide gthe run into two, returning the prefix and modifyig self.
- (CharacterRun *)splitBeforeIndex:(int)truncateBeforeIndex;

// This should be called no more than once. It uses up space in the SharedCharacterRunData.
- (NSArray *)runsWithGlyphs;

// Returns YES if the codes in otherRun can be safely added to this run.
- (BOOL)isCompatibleWith:(CharacterRun *)otherRun;

// Append to |codes|.
- (void)appendCodesFromString:(NSString *)string withAdvance:(CGFloat)advance;
- (void)appendCode:(unichar)code withAdvance:(CGFloat)advance;

// Clear the allocated range.
- (void)clearRange;

- (unichar *)codes;
- (CGSize *)advances;
- (CGGlyph *)glyphs;

@end
