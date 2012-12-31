//
//  CharacterRun.m
//  iTerm
//
//  Created by George Nachman on 12/16/12.
//
//

#import "CharacterRun.h"
#import "ScreenChar.h"

@implementation CharacterRun

@synthesize antiAlias = antiAlias_;
@synthesize color = color_;
@synthesize runType = runType_;
@synthesize fakeBold = fakeBold_;
@synthesize x = x_;
@synthesize fontInfo = fontInfo_;
@synthesize sharedData = sharedData_;
@synthesize range = range_;

- (id)init {
    self = [super init];
    if (self) {
        runType_ = kCharacterRunMultipleSimpleChars;
    }
    return self;
}

- (void)dealloc {
    [color_ release];
    [fontInfo_ release];
    [sharedData_ release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone {
    CharacterRun *theCopy = [[CharacterRun alloc] init];
    theCopy.antiAlias = antiAlias_;
    theCopy.runType = runType_;
    theCopy.fontInfo = fontInfo_;
    theCopy.color = color_;
    theCopy.fakeBold = fakeBold_;
    theCopy.x = x_;
    theCopy.sharedData = sharedData_;
    theCopy.range = range_;
    return theCopy;
}

- (NSString *)description {
    NSMutableString *d = [NSMutableString string];
    [d appendFormat:@"<CharacterRun: %p codes=\"", self];
    unichar *c = [self codes];
    for (int i = 0; i < range_.length; i++) {
        [d appendFormat:@"%x ", (((int)c[i]) & 0xffff)];
    }
    [d appendFormat:@"\">"];
    return d;
}

- (unichar *)codes {
    return [sharedData_ codesInRange:range_];
}

- (CGSize *)advances {
    return [sharedData_ advancesInRange:range_];
}

- (CGGlyph *)glyphs {
    return [sharedData_ glyphsInRange:range_];
}

// Given a run with codes x1,x2,...,xn, change self to have codes x1,x2,...,x(i-1).
// and return a new run (with the same attributes as self) with codes xi,x(i+1),...,xn.
- (CharacterRun *)splitBeforeIndex:(int)truncateBeforeIndex
{
    CharacterRun *tailRun = [[self copy] autorelease];
    assert(range_.length >= truncateBeforeIndex);
    CGSize *advances = [self advances];
    for (int i = 0; i < truncateBeforeIndex; ++i) {
        tailRun.x += advances[i].width;
    }
    [sharedData_ advanceAllocation:&tailRun->range_ by:truncateBeforeIndex];
    [sharedData_ truncateAllocation:&range_ toSize:truncateBeforeIndex];

    return tailRun;
}

// Returns the index of the first glyph in [self glyphs] valued 0, or -1 if there is none.
- (int)indexOfFirstMissingGlyph {
    CGGlyph *glyphs = [self glyphs];
    for (int i = 0; i < range_.length; i++) {
        if (!glyphs[i]) {
            return i;
        }
    }
    return -1;
}

- (void)appendRunsWithGlyphsToArray:(NSMutableArray *)newRuns {
    [newRuns addObject:self];
    if (runType_ == kCharacterRunSingleCharWithCombiningMarks) {
        // These don't actually need glyphs. This algorithm is incompatible
        // with surrogate pairs (they have expected 0-valued glyphs), so it
        // must never be used in this case. Anyway, it's useless because
        // CoreText can't render combining marks sanely.
        return;
    }

    // This algorithm works by trying to convert a whole run into glyphs. If a bad glyph is found,
    // the current run is split before and after the bad glyph. The bad glyph will be set to type
    // kCharacterRunSingleCharWithCombiningMarks and left for NSAttributedString to deal with.
    //
    // Example (numbers are valid glyphs, letters are errors):
    // 12a34bc5d
    // [12,a34bc5d]
    // [12,a,34bc5d]
    // [12,a,34,bc5d]
    // [12,a,34,b,c5d]
    // [12,a,34,b,c,5d]
    // [12,a,34,b,c,5,d]
    //
    // In the while loop, the invariant is maintained that currentRun always equals the last glyph
    // in the newRuns array.
    BOOL isOk = CTFontGetGlyphsForCharacters((CTFontRef)fontInfo_.font,
                                             [self codes],
                                             [self glyphs],
                                             range_.length);
    CharacterRun *currentRun = self;
    while (!isOk) {
        // As long as this loop is running there are bogus glyphs in the current
        // run. We split the prefix of good glyphs off and then split the suffix
        // after the bad glyph off, isolating it.
        //
        // A faster algorithm would be possible if the font substitution
        // algorithm were a bit smarter, but sometimes it goes down dead ends
        // so the only way to make sure that it can render the max number of
        // glyphs in a string is to substitute fonts for one glyph at a time.
        //
        // Example: given "U+239c U+23b7" in AndaleMono, the font substitution
        // algorithm suggests HiraganoKaguGothicProN, which cannot render both
        // glyphs. Ask it one at a time and you get Apple Symbols, which can
        // render both.
        int i = [currentRun indexOfFirstMissingGlyph];
        while (i >= 0) {
            if (i == 0) {
                // The first glyph is bad. Truncate the current run to 1
                // glyph and convert it to a
                // kCharacterRunSingleCharWithCombiningMarks (though it's
                // obviously only one code point, it uses NSAttributedString to
                // render which is slow but can find the right font).
                CharacterRun *suffixRun = [currentRun splitBeforeIndex:1];
                currentRun.runType = kCharacterRunSingleCharWithCombiningMarks;

                if (suffixRun.range.length > 0) {
                    // Append the remainder of the original run to the array of
                    // runs and have the outer loop begin working on the suffix.
                    [newRuns addObject:suffixRun];
                    currentRun = suffixRun;
                    // break to try getting glyphs again.
                    break;
                } else {
                    // This was the last glyph.
                    return;
                }
            } else if (i > 0) {
                // Some glyph after the first is bad. Truncate the current
                // run to just the good glyphs. Set the currentRun to the
                // second half. This allows us to have a long run of type kCharacterRunMultipleSimpleChars.
                currentRun = [currentRun splitBeforeIndex:i];
                [newRuns addObject:currentRun];
                // Now currentRun has a bad first glyph.
            }

            i = [currentRun indexOfFirstMissingGlyph];
        }
        if (i >= 0) {
            isOk = CTFontGetGlyphsForCharacters((CTFontRef)currentRun.fontInfo.font,
                                                [self codes],
                                                [self glyphs],
                                                currentRun.range.length);
        } else {
            break;
        }
    }
}

- (NSArray *)runsWithGlyphs
{
    if (!range_.length) {
        return nil;
    }
    NSMutableArray *newRuns = [NSMutableArray array];
    [self appendRunsWithGlyphsToArray:newRuns];
    return newRuns;
}

- (BOOL)isCompatibleWith:(CharacterRun *)otherRun {
    return (otherRun.runType != kCharacterRunSingleCharWithCombiningMarks &&
            runType_ != kCharacterRunSingleCharWithCombiningMarks &&
            fontInfo_ == otherRun.fontInfo &&
            color_ == otherRun.color &&
            fakeBold_ == otherRun.fakeBold &&
            antiAlias_ == otherRun.antiAlias);
}

- (void)appendCode:(unichar)code withAdvance:(CGFloat)advance {
    [sharedData_ growAllocation:&range_ by:1];
    unichar *codes = [self codes];
    CGSize *advances = [self advances];
    codes[range_.length - 1] = code;
    advances[range_.length - 1] = CGSizeMake(advance, 0);
}

- (void)appendCodesFromString:(NSString *)string withAdvance:(CGFloat)advance {
    int offset = range_.length;
    int length = [string length];
    [sharedData_ growAllocation:&range_ by:length];
    [string getCharacters:[self codes] + offset
                    range:NSMakeRange(0, length)];
    CGSize *advances = [self advances];
    advances[offset] = CGSizeMake(advance, 0);
}

- (void)clearRange {
    range_ = NSMakeRange(0, 0);
}

@end
