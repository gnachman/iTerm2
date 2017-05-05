//
//  PTYFontInfo.h
//  iTerm
//
//  Created by George Nachman on 12/17/12.
//
//

#import <Cocoa/Cocoa.h>

// A collection of data about a font.
@interface PTYFontInfo : NSObject

@property(nonatomic, retain) NSFont *font;
@property(nonatomic, readonly) CGFloat baselineOffset;
@property(nonatomic, readonly) CGFloat underlineOffset;
@property(nonatomic, retain) PTYFontInfo *boldVersion;
@property(nonatomic, retain) PTYFontInfo *italicVersion;
@property(nonatomic, retain) PTYFontInfo *boldItalicVersion;
@property(nonatomic, readonly) NSInteger ligatureLevel;
@property(nonatomic, readonly) BOOL hasDefaultLigatures;

+ (PTYFontInfo *)fontInfoWithFont:(NSFont *)font;

// Returns a new autorelased PTYFontInfo with a bold version of this font (or
// nil if none is available).
- (PTYFontInfo *)computedBoldVersion;

// Returns a new autorelased PTYFontInfo with a bold version of this font (or
// nil if none is available).
- (PTYFontInfo *)computedItalicVersion;


// Returns a new autorelased PTYFontInfo with a bold and italic version of this font (or nil if none
// is available).
- (PTYFontInfo *)computedBoldItalicVersion;

@end

