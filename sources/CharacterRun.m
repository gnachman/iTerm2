//
//  CharacterRun.m
//  iTerm
//
//  Created by George Nachman on 12/16/12.
//
//

#import "CharacterRun.h"
#import "ScreenChar.h"

#define SIZEOF_CODES    sizeof(*codes_)
#define SIZEOF_GLYPHS   sizeof(*glyphs_)
#define SIZEOF_ADVANCES sizeof(*advances_)
#define SIZEOF_ELEMENTS (SIZEOF_CODES + SIZEOF_GLYPHS + SIZEOF_ADVANCES)

@implementation CRunStorage {
    void *elements_;
}

+ (CRunStorage *)cRunStorageWithCapacity:(int)capacity {
    return [[[CRunStorage alloc] initWithCapacity:capacity] autorelease];
}

- (instancetype)initWithCapacity:(int)capacity {
    self = [super init];
    if (self) {
        capacity_ = MAX(capacity, 1);
        elements_ = malloc(SIZEOF_ELEMENTS * capacity_);
        [self _setElements];
        colors_ = [[NSHashTable alloc] initWithOptions:NSHashTableObjectPointerPersonality
                                              capacity:2];
        used_ = 0;
    }
    return self;
}

- (void)dealloc {
    free(elements_);
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

- (void)_setElements
{
    codes_    = elements_;
    glyphs_   = elements_ + SIZEOF_CODES * capacity_;
    advances_ = elements_ + (SIZEOF_CODES + SIZEOF_GLYPHS) * capacity_;
}

- (int)allocate:(int)size {
    int theIndex = used_;
    used_ += size;
    while (used_ > capacity_) {
        capacity_ *= 2;
        elements_ = realloc(elements_, SIZEOF_ELEMENTS * capacity_);
        [self _setElements];
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
