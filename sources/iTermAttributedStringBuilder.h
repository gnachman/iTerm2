//
//  iTermAttributedStringBuilder.h
//  iTerm2
//
//  Created by George Nachman on 10/31/24.
//

#import <Cocoa/Cocoa.h>

#import "CVector.h"
#import "ScreenChar.h"
#import "iTermBackgroundColorRun.h"
#import "iTermPreciseTimer.h"

@protocol FontProviderProtocol;
@protocol iTermAttributedString;
@class iTermBidiDisplayInfo;
@class iTermColorMap;
@protocol iTermExternalAttributeIndexReading;
@class iTermFontTable;

@protocol iTermAttributedStringBuilderDelegate<NSObject>
@property (nonatomic, readonly) BOOL useSelectedTextColor;

- (NSColor *)unprocessedColorForBackgroundRun:(const iTermBackgroundColorRun *)run
                               enableBlending:(BOOL)enableBlending;
- (NSColor *)colorForCode:(int)theIndex
                    green:(int)green
                     blue:(int)blue
                colorMode:(ColorMode)theMode
                     bold:(BOOL)isBold
                    faint:(BOOL)isFaint
             isBackground:(BOOL)isBackground;
@end

typedef struct {
    iTermPreciseTimerStats attrsForChar;
    iTermPreciseTimerStats shouldSegment;
    iTermPreciseTimerStats buildMutableAttributedString;
    iTermPreciseTimerStats combineAttributes;
    iTermPreciseTimerStats updateBuilder;
    iTermPreciseTimerStats advances;
} iTermAttributedStringBuilderStats;

typedef struct {
    iTermPreciseTimerStats *attrsForChar;
    iTermPreciseTimerStats *shouldSegment;
    iTermPreciseTimerStats *buildMutableAttributedString;
    iTermPreciseTimerStats *combineAttributes;
    iTermPreciseTimerStats *updateBuilder;
    iTermPreciseTimerStats *advances;
} iTermAttributedStringBuilderStatsPointers;

extern NSString *const iTermAntiAliasAttribute;
extern NSString *const iTermBoldAttribute;
extern NSString *const iTermFaintAttribute;
extern NSString *const iTermFakeBoldAttribute;
extern NSString *const iTermFakeItalicAttribute;
extern NSString *const iTermImageCodeAttribute;
extern NSString *const iTermImageColumnAttribute;
extern NSString *const iTermImageLineAttribute;
extern NSString *const iTermImageDisplayColumnAttribute;
extern NSString *const iTermIsBoxDrawingAttribute;
extern NSString *const iTermUnderlineLengthAttribute;
extern NSString *const iTermHasUnderlineColorAttribute;
extern NSString *const iTermUnderlineColorAttribute;
extern NSString *const iTermKittyImageRowAttribute;
extern NSString *const iTermKittyImageColumnAttribute;
extern NSString *const iTermKittyImageIDAttribute;
extern NSString *const iTermKittyImagePlacementIDAttribute;

@interface iTermAttributedStringBuilder: NSObject

@property (nonatomic, strong, readonly) iTermColorMap *colorMap;
@property (nonatomic, readonly) BOOL reverseVideo;
@property (nonatomic, readonly) CGFloat minimumContrast;
@property (nonatomic, readonly) BOOL zippy;
@property (nonatomic, readonly) BOOL asciiLigaturesAvailable;
@property (nonatomic, readonly) BOOL asciiLigatures;
@property (nonatomic, readonly) iTermAttributedStringBuilderStatsPointers stats;
@property (nonatomic, readonly) BOOL preferSpeedToFullLigatureSupport;
@property (nonatomic, readonly) NSSize cellSize;
@property (nonatomic, readonly) BOOL blinkingItemsVisible;
@property (nonatomic, readonly) BOOL blinkAllowed;
@property (nonatomic, readonly) BOOL useNonAsciiFont;
@property (nonatomic, readonly) BOOL asciiAntiAlias;
@property (nonatomic, readonly) BOOL nonAsciiAntiAlias;
@property (nonatomic, readonly) BOOL isRetina;
@property (nonatomic, readonly) BOOL forceAntialiasingOnRetina;
@property (nonatomic, strong, readonly) id<FontProviderProtocol> fontProvider;
@property (nonatomic, readonly) BOOL boldAllowed;
@property (nonatomic, readonly) BOOL italicAllowed;
@property (nonatomic, readonly) BOOL nonAsciiLigatures;
@property (nonatomic, readonly) BOOL useNativePowerlineGlyphs;
@property (nonatomic, strong) iTermFontTable *fontTable;
@property (nonatomic, readonly) NSString *statisticsString;

@property (nonatomic, weak) id<iTermAttributedStringBuilderDelegate> delegate;

- (void)setColorMap:(iTermColorMap *)colorMap
       reverseVideo:(BOOL)reverseVideo
    minimumContrast:(CGFloat)minimumContrast
              zippy:(BOOL)zippy
asciiLigaturesAvailable:(BOOL)asciiLigaturesAvailable
     asciiLigatures:(BOOL)asciiLigatures
preferSpeedToFullLigatureSupport:(BOOL)preferSpeedToFullLigatureSupport
           cellSize:(NSSize)cellSize
blinkingItemsVisible:(BOOL)blinkingItemsVisible
       blinkAllowed:(BOOL)blinkAllowed
    useNonAsciiFont:(BOOL)useNonAsciiFont
     asciiAntiAlias:(BOOL)asciiAntiAlias
  nonAsciiAntiAlias:(BOOL)nonAsciiAntiAlias
           isRetina:(BOOL)isRetina
forceAntialiasingOnRetina:(BOOL)forceAntialiasingOnRetina
        boldAllowed:(BOOL)boldAllowed
      italicAllowed:(BOOL)italicAllowed
  nonAsciiLigatures:(BOOL)nonAsciiLigatures
useNativePowerlineGlyphs:(BOOL)useNativePowerlineGlyphs
       fontProvider:(id<FontProviderProtocol>)fontProvider
          fontTable:(iTermFontTable *)fontTable
           delegate:(id<iTermAttributedStringBuilderDelegate>)delegate;

- (NSArray<id<iTermAttributedString>> *)attributedStringsForLine:(const screen_char_t *)line
                                                        bidiInfo:(iTermBidiDisplayInfo *)bidiInfo
                                              externalAttributes:(id<iTermExternalAttributeIndexReading>)eaIndex
                                                           range:(NSRange)indexRange
                                                 hasSelectedText:(BOOL)hasSelectedText
                                                 backgroundColor:(NSColor *)backgroundColor
                                                  forceTextColor:(NSColor *)forceTextColor
                                                        colorRun:(const iTermBackgroundColorRun *)colorRun
                                                     findMatches:(NSData *)findMatches
                                                 underlinedRange:(NSRange)underlinedRange
                                                       positions:(CTVector(CGFloat) *)positions;

- (void)copySettingsFrom:(iTermAttributedStringBuilder *)other
                colorMap:(iTermColorMap *)colorMap
                delegate:(id<iTermAttributedStringBuilderDelegate>)delegate;

- (instancetype)initWithStats:(const iTermAttributedStringBuilderStatsPointers)stats NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end
