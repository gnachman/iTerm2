//
//  NSCharacterSet+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 3/29/15.
//
//

#import <Foundation/Foundation.h>

@interface NSCharacterSet (iTerm)

// See EastAsianWidth.txt in Unicode 6.0.

// Full-width characters.
+ (instancetype)fullWidthCharacterSet;

// Ambiguous-width characters.
+ (instancetype)ambiguousWidthCharacterSet;

// Zero-width spaces.
+ (instancetype)zeroWidthSpaceCharacterSet;

@end
