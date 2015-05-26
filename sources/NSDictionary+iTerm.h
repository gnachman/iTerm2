//
//  NSDictionary+iTerm.h
//  iTerm
//
//  Created by George Nachman on 1/2/14.
//
//

#import <Cocoa/Cocoa.h>
#import "VT100GridTypes.h"

@interface NSDictionary (iTerm)

+ (NSDictionary *)dictionaryWithGridCoord:(VT100GridCoord)coord;
- (VT100GridCoord)gridCoord;

+ (NSDictionary *)dictionaryWithGridAbsCoord:(VT100GridAbsCoord)coord;
- (VT100GridAbsCoord)gridAbsCoord;

+ (NSDictionary *)dictionaryWithGridAbsCoordRange:(VT100GridAbsCoordRange)coordRange;
- (VT100GridAbsCoordRange)gridAbsCoordRange;

- (BOOL)boolValueDefaultingToYesForKey:(id)key;
- (NSColor *)colorValue;

// If the dict doesn't have an alpha component, use |alpha|.
- (NSColor *)colorValueWithDefaultAlpha:(CGFloat)alpha;

@end
