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

- (BOOL)boolValueDefaultingToYesForKey:(id)key;
- (NSColor *)colorValue;

// If the dict doesn't have an alpha component, use |alpha|.
- (NSColor *)colorValueWithDefaultAlpha:(CGFloat)alpha;

@end
