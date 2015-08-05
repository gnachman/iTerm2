//
//  iTermColorMap.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Cocoa/Cocoa.h>

// This would be an enum except lldb doesn't handle enums very well.
// (lldb) po [_colorMap colorForKey:kColorMapBackground]
// error: use of undeclared identifier 'kColorMapBackground'
// error: 1 errors parsing expression
// TODO: When this is fixed, change it into an enum.

typedef int iTermColorMapKey;

// Logical colors
extern const int kColorMapForeground;
extern const int kColorMapBackground;
extern const int kColorMapBold;
extern const int kColorMapLink;
extern const int kColorMapSelection;
extern const int kColorMapSelectedText;
extern const int kColorMapCursor;
extern const int kColorMapCursorText;
extern const int kColorMapInvalid;

// This value plus 0...255 are accepted. The ANSI colors below followed by their bright
// variants make the first 16 entries of the 256-color space.
extern const int kColorMap8bitBase;

// The 8 basic ANSI colors, which are within the 8-bit color range. These are
// the dark versions unless you add the bright modifier (add, don't OR).
// These are the first colors in the 8-bit range starting at kColorMap8bitBase.
extern const int kColorMapAnsiBlack;
extern const int kColorMapAnsiRed;
extern const int kColorMapAnsiGreen;
extern const int kColorMapAnsiYellow;
extern const int kColorMapAnsiBlue;
extern const int kColorMapAnsiMagenta;
extern const int kColorMapAnsiCyan;
extern const int kColorMapAnsiWhite;

// This can be added to the Ansi colors above to make them brighter.
extern const int kColorMapAnsiBrightModifier;

// This value plus 0...2^24-1 are accepted as read-only keys. These must be the highest-valued keys.
extern const int kColorMap24bitBase;

@class iTermColorMap;

@protocol iTermColorMapDelegate <NSObject>

- (void)colorMap:(iTermColorMap *)colorMap didChangeColorForKey:(iTermColorMapKey)theKey;
- (void)colorMap:(iTermColorMap *)colorMap dimmingAmountDidChangeTo:(double)dimmingAmount;
- (void)colorMap:(iTermColorMap *)colorMap mutingAmountDidChangeTo:(double)mutingAmount;

@end

// This class holds the collection of colors used by a single session. Some colors are index-mapped
// (foreground, background, etc.). An 8-bit gamut (kColorMap8bitBase to kColorMap8bitBase+255)
// exists, as does a 24-bit gamut (kColorMap24bitBase to kColorMap24bitBase+16777215). Additionally,
// two transformations on colors are performed by this class. Dimming moves colors by
// self.dimmingAmount towards a neutral gray, and is used to indicate a session's inactivity. Muting
// moves colors towards the background color and is used by the "cursor boost" feature to make the
// cursor stand out more.
@interface iTermColorMap : NSObject

@property(nonatomic, assign) BOOL dimOnlyText;
@property(nonatomic, assign) double dimmingAmount;
@property(nonatomic, assign) double mutingAmount;
@property(nonatomic, assign) id<iTermColorMapDelegate> delegate;
@property(nonatomic, assign) double minimumContrast;

+ (iTermColorMapKey)keyFor8bitRed:(int)red
                            green:(int)green
                             blue:(int)blue;

- (void)setColor:(NSColor *)theColor forKey:(iTermColorMapKey)theKey;
- (NSColor *)colorForKey:(iTermColorMapKey)theKey;

// Apply the following filters in order:
// 1. Modify textColor to have at least self.minimumContrast against backgroundColor
// 2. Average textColor proportionally with the background color by self.mutingAmount
// 3. Dim textColor proportionally with either gray or background color (depending on
//    self.dimOnlyText) by self.dimmingAmount.
// 4. Premultiply textColor's alpha with backgroundColor.
- (NSColor *)processedTextColorForTextColor:(NSColor *)textColor
                        overBackgroundColor:(NSColor*)backgroundColor;
- (NSColor *)processedBackgroundColorForBackgroundColor:(NSColor *)color;
- (NSColor *)colorByMutingColor:(NSColor *)color;
- (NSColor *)colorByDimmingTextColor:(NSColor *)color;

// Returns non-nil profile key name for valid logical colors, ANSI colors, and bright ANSI colors.
- (NSString *)profileKeyForColorMapKey:(int)theKey;

@end
