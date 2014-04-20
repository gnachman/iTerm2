//
//  NSDictionary+iTerm.h
//  iTerm
//
//  Created by George Nachman on 1/2/14.
//
//

#import <Cocoa/Cocoa.h>

@interface NSDictionary (iTerm)

- (BOOL)boolValueDefaultingToYesForKey:(id)key;
- (NSColor *)colorValue;

@end
