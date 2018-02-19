//
//  iTermColorMap.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Cocoa/Cocoa.h>
#include <simd/vector_types.h>

#import "iTermColorMapKey.h"

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
@interface iTermColorMap : NSObject<NSCopying>

@property(nonatomic, assign) BOOL dimOnlyText;
@property(nonatomic, assign) double dimmingAmount;
@property(nonatomic, assign) double mutingAmount;
@property(nonatomic, assign) id<iTermColorMapDelegate> delegate;
@property(nonatomic, assign) double minimumContrast;
@property(nonatomic, readonly) NSInteger generation;
@property(nonatomic, readonly) NSData *serializedData;

+ (iTermColorMapKey)keyFor8bitRed:(int)red
                            green:(int)green
                             blue:(int)blue;

- (void)setColor:(NSColor *)theColor forKey:(iTermColorMapKey)theKey;
- (NSColor *)colorForKey:(iTermColorMapKey)theKey;
- (vector_float4)fastColorForKey:(iTermColorMapKey)theKey;

// Apply the following filters in order:
// 1. Modify textColor to have at least self.minimumContrast against backgroundColor
// 2. Average textColor proportionally with the background color by self.mutingAmount
// 3. Dim textColor proportionally with either gray or background color (depending on
//    self.dimOnlyText) by self.dimmingAmount.
// 4. Premultiply textColor's alpha with backgroundColor.
- (NSColor *)processedTextColorForTextColor:(NSColor *)textColor
                        overBackgroundColor:(NSColor*)backgroundColor;
- (NSColor *)processedBackgroundColorForBackgroundColor:(NSColor *)color;
- (vector_float4)fastProcessedBackgroundColorForBackgroundColor:(vector_float4)backgroundColor;
- (NSColor *)colorByMutingColor:(NSColor *)color;
- (vector_float4)fastColorByMutingColor:(vector_float4)color;
- (NSColor *)colorByDimmingTextColor:(NSColor *)color;

// Returns non-nil profile key name for valid logical colors, ANSI colors, and bright ANSI colors.
- (NSString *)profileKeyForColorMapKey:(int)theKey;

@end
