//
//  PTYFontInfo.h
//  iTerm
//
//  Created by George Nachman on 12/17/12.
//
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// A collection of data about a font.
@interface PTYFontInfo : NSObject

@property(nonatomic, retain) NSFont *font;
@property(nonatomic, readonly) CGFloat baselineOffset;
@property(nonatomic, readonly) CGFloat underlineOffset;
@property(nonatomic, strong, nullable) PTYFontInfo *boldVersion;
@property(nonatomic, strong, nullable) PTYFontInfo *italicVersion;
@property(nonatomic, strong, nullable) PTYFontInfo *boldItalicVersion;
@property(nonatomic, readonly) NSInteger ligatureLevel;
@property(nonatomic, readonly) BOOL hasDefaultLigatures;

+ (PTYFontInfo *)fontInfoWithFont:(NSFont *)font;

// renderBold and renderItalic are inout parameters. Pass in whether you want bold/italic and the
// resulting value is whether it should be rendered as fake bold/italic.
+ (PTYFontInfo *)fontForAsciiCharacter:(BOOL)isAscii
                             asciiFont:(PTYFontInfo *)asciiFont
                          nonAsciiFont:(PTYFontInfo * _Nullable)nonAsciiFont
                           useBoldFont:(BOOL)useBoldFont
                         useItalicFont:(BOOL)useItalicFont
                      usesNonAsciiFont:(BOOL)useNonAsciiFont
                            renderBold:(BOOL *)renderBold
                          renderItalic:(BOOL *)renderItalic;

// Returns a new autoreleased PTYFontInfo with a bold version of this font (or
// nil if none is available).
- (PTYFontInfo * _Nullable)computedBoldVersion;

// Returns a new autoreleased PTYFontInfo with a bold version of this font (or
// nil if none is available).
- (PTYFontInfo * _Nullable)computedItalicVersion;


// Returns a new autoreleased PTYFontInfo with a bold and italic version of this font (or nil if none
// is available).
- (PTYFontInfo * _Nullable)computedBoldItalicVersion;

@end

@interface NSFont(PTYFontInfo)
@property (nonatomic, readonly) BOOL it_defaultLigatures;

// 0 means ligatures are not supported at all for this font.
@property (nonatomic, readonly) NSInteger it_ligatureLevel;

@end

NS_ASSUME_NONNULL_END
