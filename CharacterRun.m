//
//  CharacterRun.m
//  iTerm
//
//  Created by George Nachman on 12/16/12.
//
//

#import "CharacterRun.h"
#import "ScreenChar.h"

@implementation CRunStorage : NSObject {
    unichar *codes_;
    CGGlyph *glyphs_;
    NSSize *advances_;
    int capacity_;
    int used_;
}

+ (CRunStorage *)cRunStorageWithCapacity:(int)capacity {
    return [[[CRunStorage alloc] initWithCapacity:capacity] autorelease];
}

- (id)initWithCapacity:(int)capacity {
    self = [super init];
    if (self) {
        capacity = MAX(capacity, 1);
        codes_ = malloc(sizeof(unichar) * capacity);
        glyphs_ = malloc(sizeof(CGGlyph) * capacity);
        advances_ = malloc(sizeof(NSSize) * capacity);
        capacity_ = capacity;
        used_ = 0;
    }
    return self;
}

- (void)dealloc {
    free(codes_);
    free(glyphs_);
    free(advances_);
    [super dealloc];
}
    
- (unichar *)codesFromIndex:(int)theIndex {
    assert(theIndex < used_);
    return codes_ + theIndex;
}

- (CGGlyph *)glyphsFromIndex:(int)theIndex {
    assert(theIndex < used_);
    return glyphs_ + theIndex;
}

- (NSSize *)advancesFromIndex:(int)theIndex {
    assert(theIndex < used_);
    return advances_ + theIndex;
}

- (int)allocate:(int)size {
    int theIndex = used_;
    used_ += size;
    while (used_ > capacity_) {
        capacity_ *= 2;
        codes_ = realloc(codes_, sizeof(unichar) * capacity_);
        glyphs_ = realloc(glyphs_, sizeof(CGGlyph) * capacity_);
        advances_ = realloc(advances_, sizeof(NSSize) * capacity_);
    }
    return theIndex;
}

@end

static void CRunDumpWithIndex(CRun *run, int offset) {
    if (run->string) {
        NSLog(@"run[%d]=%@    advance=%f [complex]", offset++, run->string, (float)run->advances[0].width);
    } else {
        for (int i = 0; i < run->length; i++) {
            NSLog(@"run[%d]=%@    advance=%f", offset++, [NSString stringWithCharacters:run->codes + i length:1], (float)run->advances[i].width);
        }
    }
    if (run->next) {
        NSLog(@"Successor:");
        CRunDumpWithIndex(run->next, offset);
    }
}

void CRunDump(CRun *run) {
    CRunDumpWithIndex(run, 0);
}