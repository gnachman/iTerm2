//
//  CharacterRun.h
//  iTerm
//
//  Created by George Nachman on 12/16/12.
//
//

#import <Cocoa/Cocoa.h>
#import "PTYFontInfo.h"

@interface SharedCharacterRunData : NSObject {
    int capacity_;  // Allocated entries in codes, advances, glyphs arrays.
    __weak unichar *codes_;
    __weak CGSize *advances_;
    __weak CGGlyph *glyphs_;
    NSRange freeRange_;
}

@property (nonatomic, assign) __weak unichar* codes;    // Shared pointer to code point(s) for this char.
@property (nonatomic, assign) __weak CGSize* advances;  // Shared pointer to advances for each code.
@property (nonatomic, assign) __weak CGGlyph* glyphs;   // Shared pointer to glyphs for these chars (single code point only)
@property (nonatomic, assign) NSRange freeRange;        // Unused space at the end of the arrays.

+ (SharedCharacterRunData *)sharedCharacterRunDataWithCapacity:(int)capacity;

// Mark a number of cells beginning at freeRange.location as used.
- (void)advance:(int)positions;

// Makes sure there is room for at least 'space' more codes/advances/glyphs beyond what is used.
// Allocates more space if necessary. Call this before writing to shared pointers and before
// calling -advance:.
- (void)reserve:(int)space;

@end

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

// For kCharacterRunMultipleSimpleChars, there is one advance but many parallel codes/glyphs.
// For kCharacterRunSingleCharWithCombiningMarks, codes/glyphs/advances are all parallel.
- (unichar *)codes;
- (CGSize *)advances;
- (CGGlyph *)glyphs;

@end
