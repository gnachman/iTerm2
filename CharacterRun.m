//
//  CharacterRun.m
//  iTerm
//
//  Created by George Nachman on 12/16/12.
//
//

#import "CharacterRun.h"
#import "ScreenChar.h"
#import "PreferencePanel.h"

static const int kDefaultAdvancesCapacity = 100;

@interface CharacterRun ()
- (NSAttributedString *)string;
@end

@implementation CharacterRun

@synthesize antiAlias = antiAlias_;
@synthesize color = color_;
@synthesize fakeBold = fakeBold_;
@synthesize x = x_;
@synthesize fontInfo = fontInfo_;
@synthesize advancedFontRendering = advancedFontRendering_;

- (id)init {
    self = [super init];
    if (self) {
        advancesCapacity_ = kDefaultAdvancesCapacity;
        advancesSize_ = 0;
        advances_ = malloc(advancesCapacity_ * sizeof(float));
        temp_ = [[NSMutableData alloc] init];
        parts_ = [[NSMutableArray alloc] init];
        ascii_ = YES;
    }
    return self;
}

- (void)dealloc {
    [color_ release];
    [fontInfo_ release];
    [temp_ release];
    [parts_ release];
    free(advances_);
    free(glyphStorage_);
    free(advancesStorage_);

    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone {
    CharacterRun *theCopy = [[CharacterRun alloc] init];
    theCopy.antiAlias = antiAlias_;
    theCopy.fontInfo = fontInfo_;
    theCopy.color = color_;
    theCopy.fakeBold = fakeBold_;
    theCopy.x = x_;
    theCopy->advances_ = (float*)realloc(theCopy->advances_, advancesCapacity_ * sizeof(float));
    memcpy(theCopy->advances_, advances_, advancesCapacity_ * sizeof(float));
    theCopy->advancesCapacity_ = advancesCapacity_;
    theCopy->temp_ = [temp_ mutableCopy];
    theCopy->parts_ = [parts_ mutableCopy];
    theCopy->advancesSize_ = advancesSize_;
    theCopy->ascii_ = ascii_;
    theCopy.advancedFontRendering = advancedFontRendering_;
    return theCopy;
}

// Align positions into cells.
- (int)getPositions:(NSPoint *)positions
             forRun:(CTRunRef)run
    startingAtIndex:(int)firstCharacterIndex
         glyphCount:(int)glyphCount
        runWidthPtr:(CGFloat *)runWidthPtr {
    const NSPoint *suggestedPositions = CTRunGetPositionsPtr(run);
    const CFIndex *indices = CTRunGetStringIndicesPtr(run);

    int characterIndex = firstCharacterIndex;
    int indexOfFirstGlyphInCurrentCell = 0;
    CGFloat basePosition = 0;  // X coord of the current cell relative to the start of this CTRun.
    int numChars = 0;
    CGFloat width = 0;
    for (int glyphIndex = 0; glyphIndex < glyphCount; glyphIndex++) {
        if (glyphIndex == 0 || indices[glyphIndex] != characterIndex) {
            // This glyph is for a new character in the string.
            // Some characters, such as THAI CHARACTER SARA AM, are composed of
            // multiple glyphs, which is why this if statement's condition
            // isn't always true.
            if (advances_[characterIndex] > 0) {
                if (glyphIndex > 0) {
                    // Advance to the next cell.
                    basePosition += advances_[characterIndex];
                }
                indexOfFirstGlyphInCurrentCell = glyphIndex;
                width += advances_[characterIndex];
            }
            characterIndex = indices[glyphIndex];
            ++numChars;
        }
        CGFloat x = basePosition + suggestedPositions[glyphIndex].x - suggestedPositions[indexOfFirstGlyphInCurrentCell].x;
        positions[glyphIndex] = NSMakePoint(x, suggestedPositions[glyphIndex].y);
    }
    *runWidthPtr = width;
    return numChars;
}

- (NSString *)description {
    return [[self string] description];
}

- (CTLineRef)newLine {
    return CTLineCreateWithAttributedString((CFAttributedStringRef) [[[self string] copy] autorelease]);
}

- (NSAttributedString *)string {
    NSMutableAttributedString *string = [[NSMutableAttributedString alloc] init];
    for (NSArray *part in parts_) {
        NSString *s = [part objectAtIndex:0];
        NSDictionary *attributes = [part objectAtIndex:1];
        NSAttributedString *as = [[[NSAttributedString alloc] initWithString:s attributes:attributes] autorelease];
        [string appendAttributedString:as];
    }
    return string;
}

- (BOOL)isCompatibleWith:(CharacterRun *)otherRun {
    return (antiAlias_ == otherRun.antiAlias &&
            color_ == otherRun.color &&
            fakeBold_ == otherRun.fakeBold &&
            fontInfo_ == otherRun.fontInfo &&
            advancedFontRendering_ == otherRun.advancedFontRendering);
}

- (NSDictionary *)attributes {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict setObject:fontInfo_.font forKey:NSFontAttributeName];
    if (antiAlias_ && advancedFontRendering_) {
        double strokeThickness = [[PreferencePanel sharedInstance] strokeThickness];
        [dict setObject:[NSNumber numberWithDouble:strokeThickness] forKey:NSStrokeWidthAttributeName];
    }
    [dict setObject:color_ forKey:NSForegroundColorAttributeName];
    // Turn off all ligatures
    [dict setObject:[NSNumber numberWithInt:0] forKey:NSLigatureAttributeName];
    return dict;
}

- (NSAttributedString *)attributedStringForString:(NSString *)string {
    return [[[NSAttributedString alloc] initWithString:string attributes:[self attributes]] autorelease];
}

- (void)appendToAdvances:(float)advance {
    if (advancesSize_ + 1 >= advancesCapacity_) {
        advancesCapacity_ = (advancesSize_ + 1) * 2;
        advances_ = realloc(advances_, advancesCapacity_ * sizeof(float));
    }
    advances_[advancesSize_++] = advance;
}

- (void)appendCode:(unichar)code withAdvance:(CGFloat)advance {
    [temp_ appendBytes:&code length:sizeof(code)];
    [self appendToAdvances:advance];
    if (code > 127) {
        ascii_ = NO;
    }
}

- (void)appendPartWithString:(NSString *)string {
    [parts_ addObject:[NSArray arrayWithObjects:string, [self attributes], nil]];
}

- (void)commit {
    if ([temp_ length]) {
        [self appendPartWithString:[NSString stringWithCharacters:[temp_ bytes]
                                                           length:[temp_ length] / sizeof(unichar)]];
        [temp_ setLength:0];
    }
}

- (void)appendCodesFromString:(NSString *)string withAdvance:(CGFloat)advance {
    [self commit];
    for (int i = 1; i < [string length]; i++) {
        [self appendToAdvances:0];
    }
    [self appendToAdvances:advance];
    [self appendPartWithString:string];
    ascii_ = NO;
}

- (void)setAntiAlias:(BOOL)antiAlias {
    [self commit];
    antiAlias_ = antiAlias;
}

- (void)setColor:(NSColor *)color {
    [self commit];
    [color_ autorelease];
    color_ = [color retain];
}

- (void)setFontInfo:(PTYFontInfo *)fontInfo {
    [self commit];
    [fontInfo_ autorelease];
    fontInfo_ = [fontInfo retain];
}

- (BOOL)isAllAscii {
    return ascii_;
}

- (CGGlyph *)glyphs {
    assert(ascii_);
    [self commit];
    assert([parts_ count] <= 1);
    NSArray *part = [parts_ lastObject];
    if (!part) {
        return nil;
    }
    NSString *s = [part objectAtIndex:0];
    int len = [s length];
    if (len == 0) {
        return nil;
    }
    unichar chars[len];
    [s getCharacters:chars range:NSMakeRange(0, len)];

    if (glyphStorage_) {
        free(glyphStorage_);
    }
    glyphStorage_ = malloc(sizeof(CGGlyph) * len);
    CTFontGetGlyphsForCharacters((CTFontRef)fontInfo_.font,
                                 chars,
                                 glyphStorage_,
                                 len);
    return glyphStorage_;
}

- (size_t)length {
    assert(ascii_);
    [self commit];
    assert([parts_ count] <= 1);
    NSArray *part = [parts_ lastObject];
    if (!part) {
        return 0;
    }
    NSString *s = [part objectAtIndex:0];
    return [s length];
}

- (NSSize *)advances {
    if (advancesStorage_) {
        free(advancesStorage_);
    }
    size_t length = [self length];
    advancesStorage_ = malloc(sizeof(NSSize) * length);
    for (int i = 0; i < length; i++) {
        advancesStorage_[i] = NSMakeSize(advances_[i], 0);
    }
    return advancesStorage_;
}
    
@end
