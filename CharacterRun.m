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
        string_ = [[NSMutableAttributedString alloc] init];
        advancesCapacity_ = kDefaultAdvancesCapacity;
        advancesSize_ = 0;
        advances_ = malloc(advancesCapacity_ * sizeof(float));
    }
    return self;
}

- (void)dealloc {
    [color_ release];
    [fontInfo_ release];
    [string_ release];
    free(advances_);

    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone {
    CharacterRun *theCopy = [[CharacterRun alloc] init];
    theCopy.antiAlias = antiAlias_;
    theCopy.fontInfo = fontInfo_;
    theCopy.color = color_;
    theCopy.fakeBold = fakeBold_;
    theCopy.x = x_;
    theCopy->string_ = [string_ mutableCopy];
    theCopy->advances_ = (float*)malloc(advancesCapacity_ * sizeof(float));
    memcpy(theCopy->advances_, advances_, advancesCapacity_ * sizeof(float));
    theCopy->advancesCapacity_ = advancesCapacity_;
    memmove(theCopy->temp_, temp_, sizeof(temp_));
    theCopy->tempCount_ = tempCount_;
    theCopy->advancesSize_ = advancesSize_;
    theCopy.advancedFontRendering = advancedFontRendering_;
    return theCopy;
}

- (NSString *)description {
    return [string_ description];
}

- (void)updateAdvances:(CGSize *)advances
  forSuggestedAdvances:(const CGSize *)suggestedAdvances
                 count:(int)glyphCount {
    int i = 0;  // Index into suggestedAdvances (input) and advances (output)
    int j = 0;  // Index into advances_
    while (i < glyphCount) {
        if (suggestedAdvances[i].width> 0) {
            advances[i] = CGSizeMake(advances_[j], 0);
            j++;
        } else {
            advances[i] = CGSizeZero;
        }
        i++;
    }
}

- (CTLineRef)newLine {
    return CTLineCreateWithAttributedString((CFAttributedStringRef) [[string_ copy] autorelease]);
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
    if (tempCount_ == kCharacterRunTempSize) {
        [self commit];
    }
    temp_[tempCount_++] = code;
    [self appendToAdvances:advance];
}

- (void)commit {
    if (tempCount_) {
        [string_ appendAttributedString:[self attributedStringForString:[NSString stringWithCharacters:temp_ length:tempCount_]]];
        tempCount_ = 0;
    }
}

- (void)appendCodesFromString:(NSString *)string withAdvance:(CGFloat)advance {
    [self commit];
    [self appendToAdvances:advance];
    [string_ appendAttributedString:[self attributedStringForString:string]];
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

@end
