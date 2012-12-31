//
//  SharedCharacterRunData.m
//  iTerm
//
//  Created by George Nachman on 12/31/12.
//
//

#import "SharedCharacterRunData.h"

@interface SharedCharacterRunData ()

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

@implementation SharedCharacterRunData

@synthesize codes = codes_;
@synthesize advances = advances_;
@synthesize glyphs = glyphs_;
@synthesize freeRange = freeRange_;

+ (SharedCharacterRunData *)sharedCharacterRunDataWithCapacity:(int)capacity {
    SharedCharacterRunData *data = [[[SharedCharacterRunData alloc] init] autorelease];
    data->capacity_ = capacity;
    data.codes = malloc(sizeof(unichar) * capacity);
    data.advances = malloc(sizeof(CGSize) * capacity);
    data.glyphs = malloc(sizeof(CGGlyph) * capacity);
    data.freeRange = NSMakeRange(0, capacity);
    return data;
}

- (void)dealloc {
    free(codes_);
    free(advances_);
    free(glyphs_);
    [super dealloc];
}

- (void)advance:(int)positions {
    [self reserve:positions];
    freeRange_.location += positions;
    assert(freeRange_.length >= positions);
    freeRange_.length -= positions;
}

- (void)reserve:(int)space {
    if (freeRange_.length < space) {
        int newSize = (capacity_ + space) * 2;
        int growth = newSize - capacity_;
        capacity_ = newSize;
        freeRange_.length += growth;
        codes_ = realloc(codes_, sizeof(unichar) * capacity_);
        advances_ = realloc(advances_, sizeof(CGSize) * capacity_);
        glyphs_ = realloc(glyphs_, sizeof(CGGlyph) * capacity_);
    }
}

- (void)growAllocation:(NSRange *)range by:(int)growBy {
    assert(growBy > 0);
    if (!range->length) {
        assert(!range->location);
        int offset = freeRange_.location;
        [self advance:growBy];
        range->length = growBy;
        range->location = offset;
    } else {
        assert(range->length >= 0);
        assert(range->location + range->length == freeRange_.location);
        [self advance:growBy];
        range->length += growBy;
    }
}

- (unichar *)codesInRange:(NSRange)range {
    assert(range.location + range.length <= freeRange_.location);
    return codes_ + range.location;
}

- (CGSize *)advancesInRange:(NSRange)range {
    assert(range.location + range.length <= freeRange_.location);
    return advances_ + range.location;
}

- (CGGlyph *)glyphsInRange:(NSRange)range {
    assert(range.location + range.length <= freeRange_.location);
    return glyphs_ + range.location;
}

- (void)advanceAllocation:(NSRange *)range by:(int)advanceBy {
    assert(range->length >= advanceBy);
    range->location += advanceBy;
    range->length -= advanceBy;
}

- (void)truncateAllocation:(NSRange *)range toSize:(int)newSize {
    assert(newSize <= range->length);
    assert(newSize >= 0);
    range->length = newSize;
}

@end
