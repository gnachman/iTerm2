//
//  PTYFontInfo.h
//  iTerm
//
//  Created by George Nachman on 12/17/12.
//
//

#import <Cocoa/Cocoa.h>

// A collection of data about a font.
@interface PTYFontInfo : NSObject {
    NSFont *font_;
    double baselineOffset_;
    PTYFontInfo *boldVersion_;
    PTYFontInfo *italicVersion_;
}

@property (nonatomic, retain) NSFont *font;
@property (nonatomic, assign) double baselineOffset;
@property (nonatomic, retain) PTYFontInfo *boldVersion;
@property (nonatomic, retain) PTYFontInfo *italicVersion;

+ (PTYFontInfo *)fontInfoWithFont:(NSFont *)font baseline:(double)baseline;

// Returns a new autorelased PTYFontInfo with a bold version of this font (or
// nil if none is available).
- (PTYFontInfo *)computedBoldVersion;

// Returns a new autorelased PTYFontInfo with a bold version of this font (or
// nil if none is available).
- (PTYFontInfo *)computedItalicVersion;

// Returns true if this font can render this character with core text.
- (BOOL)hasGlyphForCharacter:(unichar)theChar;

@end
