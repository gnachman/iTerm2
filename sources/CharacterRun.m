//
//  CharacterRun.m
//  iTerm
//
//  Created by George Nachman on 12/16/12.
//
//

#import "CharacterRun.h"
#import "ScreenChar.h"

@implementation CRunStorage : NSObject

+ (CRunStorage *)cRunStorageWithCapacity:(int)capacity {
    return [[[CRunStorage alloc] initWithCapacity:capacity] autorelease];
}

- (instancetype)initWithCapacity:(int)capacity {
    self = [super init];
    if (self) {
        capacity = MAX(capacity, 1);
        codes_ = malloc(sizeof(unichar) * capacity);
        glyphs_ = malloc(sizeof(CGGlyph) * capacity);
        advances_ = malloc(sizeof(NSSize) * capacity);
        capacity_ = capacity;
        colors_ = [[NSHashTable alloc] initWithOptions:NSHashTableObjectPointerPersonality
                                              capacity:2];
        used_ = 0;
    }
    return self;
}

- (void)dealloc {
    free(codes_);
    free(glyphs_);
    free(advances_);
    for (NSColor *color in colors_.allObjects) {
        [color release];
    }
    [colors_ release];
    [super dealloc];
}

- (unichar *)codesFromIndex:(int)theIndex {
    assert(theIndex < used_ && theIndex >= 0);
    return codes_ + theIndex;
}

- (CGGlyph *)glyphsFromIndex:(int)theIndex {
    assert(theIndex < used_ && theIndex >= 0);
    return glyphs_ + theIndex;
}

- (NSSize *)advancesFromIndex:(int)theIndex {
    assert(theIndex < used_ && theIndex >= 0);
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

- (int)appendCode:(unichar)code andAdvance:(NSSize)advance {
    int i = [self allocate:1];
    codes_[i] = code;
    advances_[i] = advance;
    return i;
}

- (void)addColor:(NSColor *)color {
    if (![colors_ containsObject:color]) {
        [colors_ addObject:[color retain]];
    }
}

@end

static void CRunDumpWithIndex(CRun *run, int offset) {
    if (run->string) {
        NSLog(@"run[%d]=%@    advance=%f [complex]",
              offset++,
              run->string,
              run->index < 0 ? -1.0 : (float)[run->storage advancesFromIndex:run->index][0].width);
    } else {
        for (int i = 0; i < run->length; i++) {
            assert(run->index >= 0);
            NSLog(@"run[%d]=%@    advance=%f",
                  offset++,
                  [NSString stringWithCharacters:[run->storage codesFromIndex:run->index] + i length:1],
                  (float)[run->storage advancesFromIndex:run->index][i].width);
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
