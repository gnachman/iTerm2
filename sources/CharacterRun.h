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
#import "ScreenChar.h"

@class CRunSet;

// Backing storage for CRuns.
@interface CRunStorage : NSObject {
	// There are |capacity_| elements in each of these, of which |used_|
	// elements are in use. They are malloc()ed in -init, possibly realloc()ed
	// in -allocate:, and free()d in -dealloc.
    unichar *codes_;
    CGGlyph *glyphs_;
    NSSize *advances_;

    int capacity_;  // Number of elements allocated
    int used_;  // Number of elements in use.

    // Like an autorelease pool, but avoids multiple retain/release's per object.
    // Why? Who knows. Autoreleased colors were getting released prematurely and
    // causing crashes. Looks like a bug in the runtime and this is a nasty
    // workaround for it.
    NSHashTable *colors_;
}

// Create a new CRunStorage with space preallocated for |capacity| characters.
+ (CRunStorage *)cRunStorageWithCapacity:(int)capacity;

// Returns codes/glyphs/advances starting at a given |index|.
- (unichar *)codesFromIndex:(int)index;
- (CGGlyph *)glyphsFromIndex:(int)index;
- (NSSize *)advancesFromIndex:(int)index;

// Sets aside |size| characters for use in codes, glyphs, and advances, and
// returns the index of the beginning of the allocation.
- (int)allocate:(int)size;

// Returns the index of the new code
- (int)appendCode:(unichar)code andAdvance:(NSSize)advance;

// Retain a color.
- (void)addColor:(NSColor *)color;

@end

// Describes the appearance of a character.
typedef struct {
    BOOL antiAlias;           // Use anti-aliasing?
    NSColor *color;           // Foreground color. Do not assign directly to this. Use CRunAttrsSetColor().
    BOOL fakeBold;            // Should bold text be rendered by drawing text twice with a 1px shift?
    BOOL fakeItalic;          // Should text be skewed?
    BOOL underline;
    unichar imageCode;        // Gives the image code, or 0 if not an image.
    int imageLine;            // Line number of the image cell. Valid if image is positive.
    int imageColumn;          // Column number of the image cell. Valid if image is positive.
    PTYFontInfo *fontInfo;    // Font to use. WEAK.
} CAttrs;

typedef struct CRun CRun;

// A node in a linked list of |CRun|s. All the characters in a single CRun
// have the same CAttrs. A CRun may contain either an array of |codes| with
// |length| elements, or else a single character in |string| which may include
// combining marks.
struct CRun {
    CAttrs attrs;             // Attributes for this run.
    CGFloat x;                // x pixel coordinate for the run's start.
    int length;               // Number of codes/glyphs/advances.
    int index;                // -1 if nothing allocated, else start index of codes, glyphs, advances
    NSString *string;         // If set then there are no codes or glyphs, but may be advances.
    int key;                  // For complex chars, this is the key that gives the sting.
    BOOL terminated;          // No more appends allowed (will go into |next|)
    CRunStorage *storage;     // Backing store for codes, glyphs, and advances.
    int numImageCells;        // Number of consecutive image cells.
    VT100GridCoord coord;     // Origin of run. Kept to know where to redraw animated GIFs.
    CRun *next;               // Next run in linked list.
};

// See CharacterRunInline.h for functions that operate on CRun.

// NSLog human-readable representation of |run| and its linked successors.
void CRunDump(CRun *run);
